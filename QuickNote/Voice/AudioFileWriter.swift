import Foundation
@preconcurrency import AVFoundation

/// Writes the microphone's audio to a small AAC file (16 kHz, mono, ADTS) while recording, so it can be
/// sent to Gemini afterwards. The audio thread hands buffers to `append`, which converts them to the
/// file's format on the spot (the input may be 48 kHz stereo) and passes them to a serial queue to be
/// written. A failure, such as a full disk, turns the writer off quietly: the recording goes on with
/// Apple's text only.
///
/// Safe to call from any thread: the state is behind one lock, the file is only touched on the queue.
final class AudioFileWriter: @unchecked Sendable {
    /// Sample rate of the file, in Hz. Speech doesn't need more, and it keeps a 30 minute recording
    /// to a few megabytes.
    static let sampleRate = 16_000.0

    /// Where recordings are kept while they wait for Gemini: per app (Debug and Release have
    /// different bundle ids), so one never cleans up the other's files.
    static var folder: URL {
        FileManager.default.temporaryDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote", directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
    }

    /// Recordings smaller than this (bytes) hold next to nothing and are not worth keeping.
    static let minimumLeftoverBytes = 4096

    /// Deals with recordings an earlier run left behind, for example after a crash: the ones with
    /// something in them move to Unsent Recordings (an AAC stream in ADTS plays even if it was never
    /// closed), tiny ones are deleted. A file that can't be moved stays where it is.
    static func cleanUpLeftovers(from folder: URL = AudioFileWriter.folder, into unsent: URL = UnsentRecordings.folder) {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        for item in items {
            let size = (try? item.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0
            if size >= minimumLeftoverBytes {
                let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
                _ = UnsentRecordings.move(item, at: date, into: unsent)
            } else {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    /// Hands over the one input buffer of a conversion, then says there is no more for now.
    private final class OneShot: @unchecked Sendable {
        var isUsed = false
    }

    let url: URL
    private let queue = DispatchQueue(label: "AudioFileWriter")
    private let lock = NSLock()
    private let outputFormat: AVAudioFormat

    // Behind the lock.
    private var isAccepting = true
    private var hasFailed = false
    private var converter: AVAudioConverter?

    // Only on the queue.
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0

    /// Creates the file, or returns nil if that isn't possible.
    init?(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        var file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        if file == nil {
            // Some systems reject the bit rate; the encoder then picks its own.
            try? FileManager.default.removeItem(at: url)
            settings[AVEncoderBitRateKey] = nil
            file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        guard let file else { return nil }
        self.url = url
        self.file = file
        outputFormat = file.processingFormat
    }

    /// Converts the buffer and queues it to be written. Called on the audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard isAccepting, !hasFailed, buffer.frameLength > 0 else { return }

        if converter?.inputFormat != buffer.format {
            // The microphone changed. Finish what the old converter still holds before switching.
            convertLocked(nil)
            guard let new = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                hasFailed = true
                return
            }
            new.downmix = true
            converter = new
        }
        convertLocked(buffer)
    }

    /// Whether the writer is still taking audio: not finished, discarded or failed.
    var isWriting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isAccepting && !hasFailed
    }

    /// Stops accepting audio, writes what is left and closes the file. Returns nil if the writer had
    /// failed (the file is then deleted) or was already finished.
    func finish() -> (url: URL, duration: TimeInterval)? {
        lock.lock()
        guard isAccepting else {
            lock.unlock()
            return nil
        }
        isAccepting = false
        if !hasFailed {
            convertLocked(nil)
        }
        converter = nil
        lock.unlock()

        let frames = queue.sync { () -> AVAudioFramePosition in
            file?.close()
            file = nil
            return framesWritten
        }
        lock.lock()
        let failed = hasFailed
        lock.unlock()
        guard !failed else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, Double(frames) / Self.sampleRate)
    }

    /// Stops and deletes the file.
    func discard() {
        lock.lock()
        isAccepting = false
        converter = nil
        lock.unlock()
        queue.sync {
            file?.close()
            file = nil
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Converts `input` (or, with nil, whatever the converter still holds at the end of the stream) and
    /// queues the result. The lock is held.
    private func convertLocked(_ input: AVAudioPCMBuffer?) {
        guard let converter else { return }
        let capacity: AVAudioFrameCount
        if let input {
            capacity = AVAudioFrameCount((Double(input.frameLength) * Self.sampleRate / converter.inputFormat.sampleRate).rounded(.up)) + 64
        } else {
            capacity = 4096
        }
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            hasFailed = true
            return
        }
        let oneShot = OneShot()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard let input else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            if oneShot.isUsed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            oneShot.isUsed = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            hasFailed = true
            return
        }
        if output.frameLength > 0 {
            queue.async { [self] in write(output) }
        }
    }

    /// On the queue.
    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let failed = hasFailed
        lock.unlock()
        guard let file, !failed else { return }
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            lock.lock()
            hasFailed = true
            lock.unlock()
        }
    }
}
