import Foundation
@preconcurrency import AVFoundation

/// Gets a recording ready for Gemini. Recordings are lossless FLAC; if that is too big for one inline
/// request (long recordings) it is transcoded to AAC at the best bit rate that fits.
enum GeminiAudio {
    /// What to send.
    enum Plan: Equatable, Sendable {
        /// The file as it is.
        case asIs
        /// A copy transcoded to AAC at this bit rate (24 kHz, mono).
        case transcode(bitRate: Int)
        /// Not even the lowest bit rate fits.
        case tooLarge
    }

    /// AAC bit rates to try, best first. AVAudioFile refuses anything above 64 kbps at 24 kHz mono.
    static let aacBitRates = [64_000, 48_000, 32_000]

    /// Where transcoded copies are written: apart from the recordings, and per app like
    /// `AudioFileWriter.folder`, so one app emptying it at launch never hits another's copy.
    static var temporaryFolder: URL {
        FileManager.default.temporaryDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote", directoryHint: .isDirectory)
            .appending(path: "Gemini", directoryHint: .isDirectory)
    }

    /// Deletes copies an earlier run left behind.
    static func clearTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryFolder)
    }

    /// Sample rate of the transcoded AAC.
    static let aacSampleRate = 24_000.0

    /// Extra room for encoder variation, as a fraction of the estimate.
    private static let sizeSafety = 1.05

    /// Bytes per ADTS header, one per AAC frame of 1024 samples.
    private static let adtsHeaderBytes = 7.0

    /// A safe estimate of the size of `seconds` of AAC at `bitRate`, with its ADTS headers.
    static func estimatedAACBytes(seconds: TimeInterval, bitRate: Int) -> Int {
        let perSecond = Double(bitRate) / 8 + aacSampleRate / 1024 * adtsHeaderBytes
        return Int((max(0, seconds) * perSecond * sizeSafety).rounded(.up))
    }

    /// The highest bit rate whose estimated size fits in one request, or nil if none does.
    static func aacBitRate(forSeconds seconds: TimeInterval) -> Int? {
        aacBitRates.first { GeminiLimits.fitsInline(audioBytes: estimatedAACBytes(seconds: seconds, bitRate: $0)) }
    }

    /// What to do with a file of `bytes` that holds `seconds` of audio.
    static func plan(fileBytes bytes: Int, seconds: TimeInterval) -> Plan {
        if GeminiLimits.fitsInline(audioBytes: bytes) { return .asIs }
        if let bitRate = aacBitRate(forSeconds: seconds) { return .transcode(bitRate: bitRate) }
        return .tooLarge
    }

    /// The MIME type Gemini needs, from the file's extension. Unknown ones are sent as AAC.
    static func mimeType(forExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "flac": "audio/flac"
        default: "audio/aac"
        }
    }

    /// Audio ready to send. `cleanUp` deletes the temporary transcoded file, if there is one; the
    /// original is never touched.
    struct Prepared: Sendable {
        var url: URL
        var mimeType: String
        var isTemporary: Bool

        func cleanUp() {
            if isTemporary { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Picks the file to send: `url` itself if it fits, else an AAC copy in `temporaryFolder`. If the
    /// planned bit rate fails or turns out too big, lower ones are tried. Throws `GeminiError.empty`
    /// for a missing or empty file, `.tooLarge` if nothing fits, and `CancellationError` if the task
    /// is cancelled (the partial copy is deleted). Transcoding runs off the main actor.
    @concurrent static func prepare(_ url: URL, duration: TimeInterval) async throws -> Prepared {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0 else { throw GeminiError.empty }
        switch plan(fileBytes: size, seconds: duration) {
        case .asIs:
            return Prepared(url: url, mimeType: mimeType(forExtension: url.pathExtension), isTemporary: false)
        case .tooLarge:
            throw GeminiError.tooLarge
        case .transcode(let planned):
            try? FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
            let output = temporaryFolder.appending(path: "\(UUID().uuidString).aac")
            for bitRate in aacBitRates where bitRate <= planned {
                do {
                    try transcode(url, to: output, bitRate: bitRate)
                } catch {
                    try? FileManager.default.removeItem(at: output)
                    if error is CancellationError { throw error }
                    continue
                }
                // The estimate may be off: it must really fit.
                let written = (try? output.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if written > 0, GeminiLimits.fitsInline(audioBytes: written) {
                    return Prepared(url: output, mimeType: mimeType(forExtension: "aac"), isTemporary: true)
                }
                try? FileManager.default.removeItem(at: output)
            }
            throw GeminiError.tooLarge
        }
    }

    /// Carries a read error out of the converter's input block.
    private final class ErrorBox: @unchecked Sendable {
        var error: Error?
    }

    /// Converts `source` to mono AAC in ADTS at `bitRate`. Checks for cancellation on every pass and
    /// then deletes the partial file and throws `CancellationError`.
    static func transcode(_ source: URL, to destination: URL, bitRate: Int) throws {
        struct Failed: Error {}
        let input = try AVAudioFile(forReading: source)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: aacSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        let output = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let converter = AVAudioConverter(from: input.processingFormat, to: output.processingFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_384),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 32_768)
        else { throw Failed() }
        converter.downmix = true

        let readError = ErrorBox()
        while true {
            do {
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            let status = converter.convert(to: outBuffer, error: nil) { _, inputStatus in
                do {
                    inBuffer.frameLength = 0
                    try input.read(into: inBuffer)
                } catch {
                    // Reading past the end throws; any other error is checked below.
                    if input.framePosition < input.length { readError.error = error }
                    inBuffer.frameLength = 0
                }
                if inBuffer.frameLength == 0 {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let error = readError.error { throw error }
            if status == .error { throw Failed() }
            if outBuffer.frameLength > 0 { try output.write(from: outBuffer) }
            if status == .endOfStream { break }
        }
    }
}
