import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Records from the microphone and turns it into text while you speak.
///
/// Apple caps how long one recognition request may run, so a long recording is chained from several
/// requests ("segments") fed by one audio engine. When to switch is up to `SegmentScheduler`, and the
/// text of the segments is put together by `SegmentedTranscript`. Switching hands the audio to the new
/// request first and only then ends the old one, so no audio falls in a gap.
@MainActor
@Observable
final class VoiceRecorder {
    /// What a finished recording leaves behind.
    struct Recording: Sendable {
        /// What Apple's recognizer heard.
        var text: String
        /// The recorded audio, if it was kept for Gemini. The caller deletes the file.
        var audioURL: URL?
        /// Length of the audio in seconds (0 without audio).
        var duration: TimeInterval
        /// Apple's recognizer gave up during the recording, so `text` lacks the end of it.
        var appleIncomplete: Bool

        static let empty = Recording(text: "", audioURL: nil, duration: 0, appleIncomplete: false)
    }

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
    /// Apple's recognizer gave up while the audio is still being recorded for Gemini, so there is no
    /// live text any more. The pill then says the text comes after you stop.
    private(set) var appleStopped = false

    /// Called when the recorder wants to be stopped and saved by its owner: with nil when the time
    /// limit is reached, with an error when it can't go on. Called once per recording.
    @ObservationIgnored var onStopRequested: ((VoiceRecorderError?) -> Void)?

    /// How long `stop()` waits for the recognizers' last words.
    private static let finalWait: TimeInterval = 2

    @ObservationIgnored private var transcript = SegmentedTranscript()
    @ObservationIgnored private var scheduler = SegmentScheduler()
    @ObservationIgnored private var tasks: [Int: SFSpeechRecognitionTask] = [:]
    /// Never reset, so a late result from an old recording can't match a new segment.
    @ObservationIgnored private var nextGeneration = 0
    /// Bumped by `cancel()` so an awaiting `start()` or `stop()` notices it was abandoned.
    @ObservationIgnored private var recordingID = 0
    @ObservationIgnored private var stopRequested = false
    /// The finished audio file while `stop()` waits for the recognizers' last words, so `stopNow()` can
    /// still hand it over if the app quits in that moment.
    @ObservationIgnored private var finishingAudio: (url: URL, duration: TimeInterval)?
    /// Writes the audio file for Gemini; nil when no key was set up at the start or it couldn't be created.
    @ObservationIgnored private var writer: AudioFileWriter?
    /// The language chosen in Settings, nil for the system's.
    @ObservationIgnored private var chosenLanguage: String?

    @ObservationIgnored private let box = RequestBox()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?

    /// Monotonic seconds, for the scheduler.
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Removes recordings an earlier run left in the temporary folder.
    static func cleanUpLeftoverRecordings() {
        AudioFileWriter.cleanUpLeftovers()
    }

    /// Asks for the microphone and speech recognition permissions if needed, then starts listening.
    /// With `recordAudio` the audio is also saved to a file for Gemini. `language` is the on-device
    /// language chosen in Settings (nil for the system's). Throws a `VoiceRecorderError` (or
    /// `CancellationError` if `cancel()` was called meanwhile).
    func start(recordAudio: Bool = false, language: String? = nil) async throws {
        guard state == .idle else { return }
        state = .starting
        chosenLanguage = language
        let id = recordingID
        do {
            let microphoneAllowed = await SpeechPermissions.microphone()
            guard id == recordingID else { throw CancellationError() }
            guard microphoneAllowed else { throw VoiceRecorderError.microphoneDenied }
            let speechAllowed = await SpeechPermissions.speech()
            guard id == recordingID else { throw CancellationError() }
            guard speechAllowed else { throw VoiceRecorderError.speechDenied }
            try beginListening(recordAudio: recordAudio)
        } catch {
            if id == recordingID { cancel() }
            throw error
        }
    }

    private func beginListening(recordAudio: Bool) throws {
        guard let recognizer = Self.makeRecognizer(chosen: chosenLanguage), recognizer.isAvailable else {
            throw VoiceRecorderError.recognizerUnavailable
        }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceRecorderError.noInputDevice }

        self.recognizer = recognizer
        self.engine = engine
        if recordAudio {
            // If the file can't be created the recording goes on with Apple's text only.
            let url = AudioFileWriter.folder.appending(path: "\(UUID().uuidString).aac")
            writer = AudioFileWriter(url: url)
            box.swapWriter(writer)
        }
        scheduler.begin(at: now)
        beginSegment()
        box.installTap(on: engine.inputNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceRecorderError.noInputDevice
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.inputConfigurationChanged() }
        }

        startedAt = .now
        state = .recording
        startTicker()
    }

    /// Stops listening, waits briefly for the recognizers' last words and returns what Apple heard and
    /// the audio file, if one was kept.
    func stop() async -> Recording {
        guard state == .recording else { return .empty }
        state = .finishing
        let id = recordingID
        let writer = writer
        self.writer = nil
        stopListening()
        let audio = writer?.finish()
        finishingAudio = audio

        let deadline = Date.now.addingTimeInterval(Self.finalWait)
        while transcript.hasPending, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        finishingAudio = nil
        guard id == recordingID else {
            if let audio { try? FileManager.default.removeItem(at: audio.url) }
            return .empty
        }

        let text = transcript.text
        let incomplete = appleStopped
        reset()
        return Recording(text: text, audioURL: audio?.url, duration: audio?.duration ?? 0, appleIncomplete: incomplete)
    }

    /// Like `stop()` but at once, without waiting for the recognizers' last words: for when the app
    /// is quitting. What was recognized so far is returned.
    func stopNow() -> Recording {
        guard state == .recording || state == .finishing else { return .empty }
        var audio = finishingAudio
        if state == .recording {
            let writer = writer
            self.writer = nil
            stopListening()
            audio = writer?.finish()
        }
        finishingAudio = nil
        let text = transcript.text
        let incomplete = appleStopped || transcript.hasPending
        recordingID += 1
        reset()
        return Recording(text: text, audioURL: audio?.url, duration: audio?.duration ?? 0, appleIncomplete: incomplete)
    }

    /// Throws the recording away.
    func cancel() {
        recordingID += 1
        stopListening()
        reset()
    }

    /// Stops the engine and the timer and ends the audio of the last request. Recognition tasks stay
    /// alive so they can deliver their last words.
    private func stopListening() {
        ticker?.cancel()
        ticker = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        box.swapWriter(nil)
        box.swap(to: nil)?.endAudio()
    }

    private func reset() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        writer?.discard()
        writer = nil
        finishingAudio = nil
        appleStopped = false
        transcript = SegmentedTranscript()
        recognizer = nil
        stopRequested = false
        liveText = ""
        level = 0
        startedAt = nil
        state = .idle
    }

    /// The recognizer for the language chosen in Settings, else the user's language, or the system's
    /// default one.
    private static func makeRecognizer(chosen: String?) -> SFSpeechRecognizer? {
        let supported = SFSpeechRecognizer.supportedLocales()
        let identifier = RecognizerLocale.choose(
            current: Locale.current.identifier,
            preferred: Locale.preferredLanguages,
            supported: Set(supported.map(\.identifier)),
            chosen: chosen
        )
        if let locale = supported.first(where: { $0.identifier == identifier }),
           let recognizer = SFSpeechRecognizer(locale: locale) {
            return recognizer
        }
        return SFSpeechRecognizer()
    }

    /// The microphone changed (headphones plugged in, a device unplugged). The engine has stopped; this
    /// moves the audio to a new request first (the one in use was fed the old format), then puts the tap
    /// back and restarts the engine.
    private func inputConfigurationChanged() {
        guard state == .recording, !stopRequested, let engine else { return }
        rotate()
        engine.inputNode.removeTap(onBus: 0)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            requestStop(.inputLost)
            return
        }
        box.installTap(on: engine.inputNode, format: nil)
        engine.prepare()
        restart(engine, mayRetry: true)
    }

    /// Starts the engine again. The system can still be busy switching devices, so one failure is
    /// retried after a moment before the recording is given up.
    private func restart(_ engine: AVAudioEngine, mayRetry: Bool) {
        do {
            try engine.start()
        } catch {
            guard mayRetry else {
                requestStop(.inputLost)
                return
            }
            let id = recordingID
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, id == recordingID, state == .recording, !stopRequested else { return }
                restart(engine, mayRetry: false)
            }
        }
    }

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
        transcript.begin(generation: generation)
        tasks[generation] = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, startsAt, endsAt, isLast in
            Task { @MainActor in
                self?.handleResult(generation: generation, text: text, startsAt: startsAt, endsAt: endsAt, isLast: isLast)
            }
        }
        return box.swap(to: request)
    }

    /// Moves the audio to a fresh request, then ends the old one so its recognizer can finish.
    private func rotate() {
        guard !appleStopped else { return }
        scheduler.segmentStarted(at: now)
        beginSegment()?.endAudio()
    }

    private func handleResult(generation: Int, text: String?, startsAt: TimeInterval?, endsAt: TimeInterval?, isLast: Bool) {
        let closedCurrent = transcript.receive(
            generation: generation, text: text, startsAt: startsAt, endsAt: endsAt, isLast: isLast
        )
        if isLast { tasks[generation] = nil }
        refreshLiveText()

        // The recognizer closed the segment itself (a pause, or an error) while we're still listening.
        if closedCurrent, state == .recording {
            perform(scheduler.segmentEnded(at: now, heardText: transcript.lastEndedHeardText))
        }
    }

    private func refreshLiveText() {
        let text = transcript.text
        if text != liveText { liveText = text }
    }

    private func perform(_ action: SegmentScheduler.Action) {
        guard !stopRequested else { return }
        switch action {
        case .none:
            break
        case .rotate:
            rotate()
        case .autoStop:
            requestStop(nil)
        case .giveUp:
            if writer?.isWriting == true {
                stopApple()
            } else {
                requestStop(.recognitionStopped)
            }
        }
    }

    /// Apple's recognizer keeps failing, but the audio is being kept for Gemini, so the recording goes
    /// on. Ends the audio of the last request and stops handing it new ones.
    private func stopApple() {
        guard !appleStopped else { return }
        appleStopped = true
        box.swap(to: nil)?.endAudio()
    }

    private func requestStop(_ error: VoiceRecorderError?) {
        guard !stopRequested else { return }
        stopRequested = true
        onStopRequested?(error)
    }

    private func startTicker() {
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// Ten times a second: updates the level and lets the scheduler decide what to do.
    private func tick() {
        guard state == .recording else { return }
        // With Apple's text gone, the audio file is all that is left; if that fails too, stop.
        if appleStopped, writer?.isWriting != true {
            requestStop(.recognitionStopped)
        }
        let loudness = SegmentScheduler.loudness(rms: box.takePeak())
        level = max(loudness, level * 0.6)
        perform(scheduler.tick(at: now, loudness: loudness))
    }

    /// Runs the recognition on Speech's queues. This is nonisolated and only touches Sendable values,
    /// so Swift 6 doesn't trap on a main-actor closure running elsewhere.
    ///
    /// `handler` gets the text so far (nil if none), when its first word begins and its last word ends,
    /// and whether the recognizer is done with this request (its last result, or a failure).
    nonisolated private static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, TimeInterval?, TimeInterval?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let transcription = result?.bestTranscription
            let last = transcription?.segments.last
            handler(
                transcription?.formattedString,
                transcription?.segments.first?.timestamp,
                last.map { $0.timestamp + $0.duration },
                (result?.isFinal ?? false) || error != nil
            )
        }
    }
}
