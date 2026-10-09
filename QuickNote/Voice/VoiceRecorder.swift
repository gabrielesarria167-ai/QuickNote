import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Why a recording couldn't start. The messages are shown to the user in the recording pill.
enum VoiceRecorderError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "QuickNote can't hear you. Allow it under System Settings → Privacy & Security → Microphone."
        case .speechDenied:
            "QuickNote can't turn speech into text. Allow it under System Settings → Privacy & Security → Speech Recognition."
        case .recognizerUnavailable:
            "Speech recognition isn't available for your language right now."
        case .noInputDevice:
            "QuickNote couldn't open a microphone. Check that one is connected."
        }
    }
}

/// Records from the microphone and turns it into text while you speak.
///
/// Apple caps how long one recognition request may run, so a long recording is chained from several
/// requests ("segments") fed by one audio engine. Segments are rotated at a quiet moment after 45 s
/// (at 55 s regardless), or whenever the recognizer ends one on its own after a pause. Rotating hands
/// the audio to the new request first and only then ends the old one, so no audio falls in a gap.
///
/// Seams: every segment keeps its own text, in speaking order, until its recognizer has said its last
/// word. A segment that was rotated out keeps updating until then, and `liveText` is simply the
/// committed text followed by every segment still pending, so nothing is dropped or said twice.
@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle
        case starting
        case recording
        case finishing
    }

    private(set) var state: State = .idle
    /// Everything recognized so far, including what's still being worked out.
    private(set) var liveText = ""
    /// How loud it is right now, 0…1.
    private(set) var level = 0.0
    /// When recording began; the pill works out the elapsed time from it.
    private(set) var startedAt: Date?

    /// Called once if the recording hits the safety limit. The owner should stop and save it.
    @ObservationIgnored var onAutoStop: (() -> Void)?

    // MARK: Timing

    /// Safety stop, in case a recording is forgotten.
    private static let maxDuration: TimeInterval = 30 * 60
    /// A segment becomes due for rotation after this long, at the next quiet moment...
    private static let rotateAfter: TimeInterval = 45
    /// ...and is rotated regardless after this long.
    private static let forceRotateAt: TimeInterval = 55
    /// Below this level (0…1) counts as quiet,
    private static let quietLevel = 0.2
    /// and a pause is this long.
    private static let quietDuration: TimeInterval = 0.3
    /// A segment the recognizer ended on its own isn't replaced sooner than this, so a recognizer that
    /// keeps failing can't spin.
    private static let minSegmentAge: TimeInterval = 1
    /// How long `stop()` waits for the recognizers' last words.
    private static let finalWait: TimeInterval = 2

    // MARK: State

    /// One recognition request's share of the transcript.
    private struct Segment {
        let generation: Int
        var text = ""
        /// The recognizer has said its last word (or failed; the last partial is then kept).
        var isFinal = false
        var task: SFSpeechRecognitionTask?
    }

    @ObservationIgnored private var accumulator = TranscriptAccumulator()
    /// Segments not yet committed, in speaking order. The last one is receiving audio.
    @ObservationIgnored private var segments: [Segment] = []
    /// Never reset, so a late result from an old recording can't match a new segment.
    @ObservationIgnored private var nextGeneration = 0
    @ObservationIgnored private var currentGeneration = -1
    @ObservationIgnored private var segmentStartedAt = Date.now
    /// The current segment ended by itself too young to be replaced yet.
    @ObservationIgnored private var rotationPending = false
    @ObservationIgnored private var quietSince: Date?
    @ObservationIgnored private var autoStopFired = false
    /// Bumped by `cancel()` so an awaiting `start()` or `stop()` notices it was abandoned.
    @ObservationIgnored private var epoch = 0

    @ObservationIgnored private let box = RequestBox()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    // MARK: Start

    /// Asks for the microphone and speech recognition permissions if needed, then starts listening.
    /// Throws a `VoiceRecorderError` (or `CancellationError` if `cancel()` was called meanwhile).
    func start() async throws {
        guard state == .idle else { return }
        state = .starting
        let epoch = self.epoch
        do {
            guard await Self.microphoneAccess() else { throw VoiceRecorderError.microphoneDenied }
            guard await Self.speechAccess() else { throw VoiceRecorderError.speechDenied }
            guard epoch == self.epoch else { throw CancellationError() }
            try beginListening()
        } catch {
            if epoch == self.epoch { cancel() }
            throw error
        }
    }

    private func beginListening() throws {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else { throw VoiceRecorderError.recognizerUnavailable }

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceRecorderError.noInputDevice }

        self.recognizer = recognizer
        self.engine = engine
        beginSegment()
        Self.installTap(on: engine.inputNode, format: format, box: box)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceRecorderError.noInputDevice
        }

        startedAt = .now
        state = .recording
        startTicker()
    }

    // MARK: Stop

    /// Stops listening, waits briefly for the recognizers' last words and returns the whole transcript.
    func stop() async -> String {
        guard state == .recording else { return "" }
        state = .finishing
        let epoch = self.epoch
        stopListening()
        rotationPending = false

        let deadline = Date.now.addingTimeInterval(Self.finalWait)
        while segments.contains(where: { !$0.isFinal }), Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard epoch == self.epoch else { return "" }

        let text = combinedText()
        reset()
        return text
    }

    /// Throws the recording away.
    func cancel() {
        epoch += 1
        stopListening()
        reset()
    }

    /// Stops the engine and the timer and ends the audio of the last request. Recognition tasks stay
    /// alive so they can deliver their last words.
    private func stopListening() {
        ticker?.cancel()
        ticker = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        box.swap(to: nil)?.endAudio()
    }

    private func reset() {
        for segment in segments {
            segment.task?.cancel()
        }
        segments = []
        accumulator = TranscriptAccumulator()
        recognizer = nil
        rotationPending = false
        quietSince = nil
        autoStopFired = false
        liveText = ""
        level = 0
        startedAt = nil
        state = .idle
    }

    // MARK: Segments

    /// Starts a new request and makes it the one receiving audio. Returns the request it replaced, which
    /// the caller ends once the swap is done.
    @discardableResult
    private func beginSegment() -> SFSpeechAudioBufferRecognitionRequest? {
        guard let recognizer else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.taskHint = .dictation

        let generation = nextGeneration
        nextGeneration += 1
        let task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in
                self?.handleResult(generation: generation, text: text, isFinal: isFinal, failed: failed)
            }
        }
        segments.append(Segment(generation: generation, task: task))
        currentGeneration = generation
        segmentStartedAt = .now
        rotationPending = false
        return box.swap(to: request)
    }

    /// Moves the audio to a fresh request, then ends the old one so its recognizer can finish.
    private func rotate() {
        beginSegment()?.endAudio()
    }

    private func handleResult(generation: Int, text: String?, isFinal: Bool, failed: Bool) {
        guard let index = segments.firstIndex(where: { $0.generation == generation }),
              !segments[index].isFinal
        else { return }

        // An empty answer never replaces text already heard.
        if let text, !text.isEmpty {
            segments[index].text = text
        }
        if isFinal || failed {
            segments[index].isFinal = true
        }
        let endedByItself = segments[index].isFinal
        flushFinishedSegments()
        refreshLiveText()

        // The recognizer closed the segment itself (a pause, or an error) while we're still listening.
        if endedByItself, generation == currentGeneration, state == .recording {
            if Date.now.timeIntervalSince(segmentStartedAt) >= Self.minSegmentAge {
                rotate()
            } else {
                rotationPending = true
            }
        }
    }

    /// Moves segments that have said their last word, from the front, into the accumulator. A finished
    /// segment behind an unfinished one waits, which keeps the order of speech.
    private func flushFinishedSegments() {
        while let first = segments.first, first.isFinal {
            accumulator.commitSegment(final: first.text)
            segments.removeFirst()
        }
    }

    private func combinedText() -> String {
        ([accumulator.text] + segments.map(\.text))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func refreshLiveText() {
        let text = combinedText()
        if text != liveText { liveText = text }
    }

    // MARK: Ticking

    private func startTicker() {
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// Ten times a second: updates the level, rotates segments and watches the safety limit.
    private func tick() {
        guard state == .recording, let startedAt else { return }
        let now = Date.now

        let loudness = Self.normalized(rms: box.takePeak())
        level = max(loudness, level * 0.6)
        if loudness < Self.quietLevel {
            quietSince = quietSince ?? now
        } else {
            quietSince = nil
        }

        let age = now.timeIntervalSince(segmentStartedAt)
        let quietFor = quietSince.map { now.timeIntervalSince($0) } ?? 0
        if rotationPending {
            if age >= Self.minSegmentAge { rotate() }
        } else if age >= Self.forceRotateAt || (age >= Self.rotateAfter && quietFor >= Self.quietDuration) {
            rotate()
        }

        if now.timeIntervalSince(startedAt) >= Self.maxDuration, !autoStopFired {
            autoStopFired = true
            onAutoStop?()
        }
    }

    /// Maps an RMS amplitude to 0…1 on a decibel scale (-45 dB and below is 0, -15 dB and above is 1).
    nonisolated static func normalized(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 45) / 30, 0), 1)
    }

    // MARK: Off the main actor
    // These run on the audio thread or Speech's queues. They're nonisolated and only touch Sendable
    // values, so Swift 6 doesn't trap on a main-actor closure running elsewhere.

    nonisolated private static func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default:
            return false
        }
    }

    nonisolated private static func speechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default:
            return false
        }
    }

    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, box: RequestBox) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.append(buffer)
        }
    }

    /// `handler` gets the text so far (nil if none), whether it's the last word, and whether the task failed.
    nonisolated private static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}

/// Hands microphone buffers from the audio thread to whichever request is current, and the loudest
/// level heard since the last time it was asked for. Everything is behind one lock.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var peak: Float = 0

    /// Makes `new` the current request and returns the one it replaces. Once this returns, the audio
    /// thread no longer touches the old request, so it's safe to end.
    func swap(to new: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = new
        return old
    }

    /// Audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        var sum: Float = 0
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            for index in 0..<Int(buffer.frameLength) {
                sum += samples[index] * samples[index]
            }
            sum = (sum / Float(buffer.frameLength)).squareRoot()
        }
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
        peak = max(peak, sum)
    }

    /// The loudest RMS since the last call.
    func takePeak() -> Float {
        lock.lock()
        defer { lock.unlock() }
        let value = peak
        peak = 0
        return value
    }
}
