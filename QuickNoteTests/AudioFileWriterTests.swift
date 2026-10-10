import Foundation
import Testing
@preconcurrency import AVFoundation
@testable import QuickNote

struct AudioFileWriterTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "AudioFileWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "test.aac")
    }

    /// A sine wave of `seconds` length in the standard (Float32, non-interleaved) format.
    private func sine(sampleRate: Double, channels: AVAudioChannelCount, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                samples[frame] = 0.5 * sin(Float(2 * Double.pi * 440 * Double(frame) / sampleRate))
            }
        }
        return buffer
    }

    @Test func writesA16kHzMonoFileFromChangingInputFormats() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try #require(AudioFileWriter(url: url))

        for _ in 0..<3 {
            writer.append(sine(sampleRate: 48_000, channels: 2, seconds: 1))
        }
        writer.append(sine(sampleRate: 44_100, channels: 1, seconds: 1))
        let result = try #require(writer.finish())

        #expect(result.url == url)
        #expect(abs(result.duration - 4) < 0.3)

        let file = try AVAudioFile(forReading: url)
        #expect(file.processingFormat.sampleRate == 24_000)
        #expect(file.processingFormat.channelCount == 1)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(abs(seconds - 4) < 0.5)
    }

    @Test func theFileHasSoundInIt() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try #require(AudioFileWriter(url: url))
        writer.append(sine(sampleRate: 48_000, channels: 2, seconds: 1))
        _ = try #require(writer.finish())

        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max() ?? 0
        #expect(peak > 0.2)
    }

    @Test func finishingTwiceGivesNothingTheSecondTime() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try #require(AudioFileWriter(url: url))
        writer.append(sine(sampleRate: 48_000, channels: 1, seconds: 0.5))
        #expect(writer.finish() != nil)
        #expect(writer.finish() == nil)
        writer.append(sine(sampleRate: 48_000, channels: 1, seconds: 0.5))
    }

    @Test func discardingDeletesTheFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try #require(AudioFileWriter(url: url))
        writer.append(sine(sampleRate: 48_000, channels: 2, seconds: 0.5))
        writer.discard()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(writer.finish() == nil)
    }

    @Test func aRecordingWithNoAudioHasNoDuration() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try #require(AudioFileWriter(url: url))
        let result = try #require(writer.finish())
        #expect(result.duration == 0)
    }

    @Test func aWriterIsWritingUntilItIsFinished() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let writer = try #require(AudioFileWriter(url: url))
        #expect(writer.isWriting)
        _ = writer.finish()
        #expect(!writer.isWriting)
    }

    @Test func leftoversWithSomethingInThemAreMovedAndTinyOnesDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AudioFileWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let leftovers = root.appending(path: "Recordings", directoryHint: .isDirectory)
        let unsent = root.appending(path: "Unsent", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftovers, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: leftovers.appending(path: "big.aac"))
        try Data(repeating: 1, count: 100).write(to: leftovers.appending(path: "tiny.aac"))

        AudioFileWriter.cleanUpLeftovers(from: leftovers, into: unsent)

        #expect(try FileManager.default.contentsOfDirectory(atPath: leftovers.path).isEmpty)
        #expect(UnsentRecordings.count(in: unsent) == 1)
    }
}
