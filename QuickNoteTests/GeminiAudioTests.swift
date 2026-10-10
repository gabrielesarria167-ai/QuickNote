import Foundation
import Testing
@preconcurrency import AVFoundation
@testable import QuickNote

struct GeminiAudioTests {
    /// A rough FLAC size for speech at 16 kHz mono (24 bit in practice), in bytes per second.
    private let flacBytesPerSecond = 36_000

    @Test func aMinuteOfFLACIsSentAsItIs() {
        #expect(GeminiAudio.plan(fileBytes: 60 * flacBytesPerSecond, seconds: 60) == .asIs)
    }

    @Test func aTwentyMinuteFLACIsTranscodedToAHighBitRateThatFits() throws {
        let plan = GeminiAudio.plan(fileBytes: 20 * 60 * flacBytesPerSecond, seconds: 20 * 60)
        #expect(plan == .transcode(bitRate: 64_000))
    }

    @Test func aThirtyMinuteRecordingGetsARateThatFits() throws {
        let seconds = 30.0 * 60
        let plan = GeminiAudio.plan(fileBytes: Int(seconds) * flacBytesPerSecond, seconds: seconds)
        guard case .transcode(let bitRate) = plan else {
            Issue.record("expected a transcode, got \(plan)")
            return
        }
        #expect(GeminiAudio.aacBitRates.contains(bitRate))
        #expect(GeminiLimits.fitsInline(audioBytes: GeminiAudio.estimatedAACBytes(seconds: seconds, bitRate: bitRate)))
    }

    @Test func theBitRateFallsAsTheRecordingGetsLonger() {
        let rates = [60.0, 600, 1200, 1800].compactMap { GeminiAudio.aacBitRate(forSeconds: $0) }
        #expect(rates.count == 4)
        #expect(rates == rates.sorted(by: >))
        #expect(rates.first == 64_000)
        #expect(rates.last == 48_000)
    }

    @Test func nothingFitsIfEvenTheLowestRateIsTooBig() {
        #expect(GeminiAudio.aacBitRate(forSeconds: 4 * 3600) == nil)
        #expect(GeminiAudio.plan(fileBytes: 100_000_000, seconds: 4 * 3600) == .tooLarge)
    }

    @Test func theMimeTypeComesFromTheExtension() {
        #expect(GeminiAudio.mimeType(forExtension: "flac") == "audio/flac")
        #expect(GeminiAudio.mimeType(forExtension: "FLAC") == "audio/flac")
        #expect(GeminiAudio.mimeType(forExtension: "aac") == "audio/aac")
        #expect(GeminiAudio.mimeType(forExtension: "") == "audio/aac")
    }

    @Test func transcodingAFLACGivesAnAACFileOfTheSameLength() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GeminiAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "in.flac")
        let writer = try #require(AudioFileWriter(url: source))
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for i in 0..<48_000 {
            buffer.floatChannelData![0][i] = 0.3 * sin(Float(2 * Double.pi * 300 * Double(i) / 16_000))
        }
        writer.append(buffer)
        _ = try #require(writer.finish())

        let output = folder.appending(path: "out.aac")
        for bitRate in GeminiAudio.aacBitRates {
            try? FileManager.default.removeItem(at: output)
            try GeminiAudio.transcode(source, to: output, bitRate: bitRate)

            let file = try AVAudioFile(forReading: output)
            #expect(file.processingFormat.sampleRate == 24_000)
            #expect(abs(Double(file.length) / 24_000 - 3) < 0.2)
        }
    }

    @Test func aCancelledTranscodeThrowsCancellationAndLeavesNoFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GeminiAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "in.flac")
        let writer = try #require(AudioFileWriter(url: source))
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        writer.append(buffer)
        _ = try #require(writer.finish())
        let output = folder.appending(path: "out.aac")

        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try GeminiAudio.transcode(source, to: output, bitRate: 48_000)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        #expect(await task.value)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func aSmallFileIsPreparedAsItIsAndNotCleanedUp() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GeminiAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "a.flac")
        try Data(repeating: 1, count: 1000).write(to: url)

        let prepared = try await GeminiAudio.prepare(url, duration: 10)
        #expect(prepared.url == url)
        #expect(prepared.mimeType == "audio/flac")
        prepared.cleanUp()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
