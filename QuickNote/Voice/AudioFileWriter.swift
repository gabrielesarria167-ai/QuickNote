import Foundation
@preconcurrency import AVFoundation

/// Writes the microphone's audio to a lossless FLAC file (16 kHz, mono; Apple's encoder
/// stores 24 bit whatever is asked) while recording, so it
/// can be sent to Gemini afterwards. Gemini downsamples everything to 16 kHz, so a higher rate would
/// only make the file bigger. The audio thread hands buffers to `append`, which converts them to the
/// file's format on the spot (the input may be 48 kHz stereo) and passes them to a serial queue to be
/// written. A failure, such as a full disk, turns the writer off quietly: the recording goes on with
/// Apple's text only. If the system can't create a FLAC file, the writer falls back to AAC (see
/// `init`); `GeminiAudio` shrinks a FLAC that is too big for one request when it is sent.
///
/// Safe to call from any thread: the state is behind one lock, the file is only touched on the queue.
final class AudioFileWriter: @unchecked Sendable {
    /// Sample rate of the FLAC file, in Hz: what Gemini works with.
    static let sampleRate = 16_000.0

    /// Sample rate and bit rate of the AAC fallback. 30 minutes at 48 kbps is about 11.1 MB with the
    /// ADTS headers, 14.8 MB as base64.
    static let fallbackSampleRate = 24_000.0
    static let fallbackBitRate = 48_000

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
    /// something in them move to Unsent Recordings, tiny ones are deleted. ADTS AAC plays even if the
    /// file was never closed; a FLAC doesn't (its header is still all zeros), so it is repaired first
    /// with `repairFLAC`. One that isn't a FLAC or still won't open is deleted; one that couldn't be
    /// read or written stays where it is, as does a file that can't be moved.
    static func cleanUpLeftovers(from folder: URL = AudioFileWriter.folder, into unsent: URL = UnsentRecordings.folder) {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        for item in items {
            let size = (try? item.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0
            if size >= minimumLeftoverBytes {
                if item.pathExtension == "flac" {
                    switch repairFLAC(item) {
                    case .opens: break
                    case .broken:
                        try? FileManager.default.removeItem(at: item)
                        continue
                    case .unreachable: continue
                    }
                }
                let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
                _ = UnsentRecordings.move(item, at: date, into: unsent)
            } else {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    /// Makes sure the FLAC file opens, fixing an unclosed one in place: the encoder only fills in the
    /// STREAMINFO block (bytes 4..<42, after "fLaC") when it closes the file. The block is rewritten for
    /// 16 kHz mono 24 bit with the sample count unknown (0).
    @discardableResult
    static func repairFLAC(_ url: URL) -> FLACRepair {
        if (try? AVAudioFile(forReading: url)) != nil { return .opens }
        guard let handle = try? FileHandle(forUpdating: url) else { return .unreachable }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4) else { return .unreachable }
        guard magic == Data("fLaC".utf8) else { return .broken }

        var block = Data([0x00, 0x00, 0x00, 0x22])
        block += [0x12, 0x00, 0x12, 0x00]                      // min and max block size: 4608
        block += [0, 0, 0, 0, 0, 0]                            // min and max frame size: unknown
        // 20 bits sample rate, 3 bits channels - 1, 5 bits bits per sample - 1, 36 bits total samples.
        let packed = UInt64(16_000) << 44 | UInt64(0) << 41 | UInt64(23) << 36
        block += (0..<8).map { UInt8(truncatingIfNeeded: packed >> UInt64(56 - 8 * $0)) }
        block += Data(count: 16)                               // MD5: unknown
        do {
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: block)
            try handle.close()
        } catch {
            return .unreachable
        }
        return (try? AVAudioFile(forReading: url)) != nil ? .opens : .broken
    }

    /// What `repairFLAC` found: the file opens (now), it is no FLAC or stays broken, or it couldn't
    /// be read or written (a permissions problem, say), so nothing is known about it.
    enum FLACRepair {
        case opens, broken, unreachable
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

    /// Creates the file, or returns nil if that isn't possible. `url` should end in `.flac`; if FLAC
    /// can't be written (or `lossless` is false) the file is AAC at `url` with an `.aac` extension
    /// instead, and `url` says which.
    init?(url: URL, lossless: Bool = true) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var file: AVAudioFile?
        var url = url
        if lossless {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: Self.sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
            file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            if file == nil { try? FileManager.default.removeItem(at: url) }
        }
        if file == nil {
            url = url.deletingPathExtension().appendingPathExtension("aac")
            var settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Self.fallbackSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: Self.fallbackBitRate,
            ]
            file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            if file == nil {
                // Some systems reject the bit rate; the encoder then picks its own.
                try? FileManager.default.removeItem(at: url)
                settings[AVEncoderBitRateKey] = nil
                file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            }
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
        return (url, Double(frames) / outputFormat.sampleRate)
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
            capacity = AVAudioFrameCount((Double(input.frameLength) * outputFormat.sampleRate / converter.inputFormat.sampleRate).rounded(.up)) + 64
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
