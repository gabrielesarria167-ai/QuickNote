import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Hands microphone buffers from the audio thread to whichever recognition request is current and to
/// the audio file writer, if there is one, and the loudest level heard since the last time it was asked
/// for. Everything is behind one lock.
final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var writer: AudioFileWriter?
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

    /// Makes `new` the writer receiving the audio and returns the one it replaces. The writer is
    /// thread-safe itself, so the caller may finish the old one right away.
    @discardableResult
    func swapWriter(_ new: AudioFileWriter?) -> AudioFileWriter? {
        lock.lock()
        defer { lock.unlock() }
        let old = writer
        writer = new
        return old
    }

    /// The loudest RMS since the last call.
    func takePeak() -> Float {
        lock.lock()
        defer { lock.unlock() }
        let value = peak
        peak = 0
        return value
    }

    /// Starts feeding the microphone into the current request. The tap runs on the audio thread, so
    /// this is nonisolated and the closure captures only the box. With no `format` the tap gets whatever
    /// the input delivers.
    nonisolated func installTap(on input: AVAudioInputNode, format: AVAudioFormat?) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] buffer, _ in
            append(buffer)
        }
    }

    /// The microphone and the Mac's audio arrive as separate channels of one aggregate device; the
    /// recognizer and the file want one, so they are summed (clamped against clipping).
    private static func mono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let channels = Int(buffer.format.channelCount)
        guard channels > 1, let source = buffer.floatChannelData,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate, channels: 1, interleaved: false),
              let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let target = result.floatChannelData?[0] else { return buffer }
        result.frameLength = buffer.frameLength
        for frame in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for channel in 0..<channels { sum += source[channel][frame] }
            target[frame] = max(-1, min(1, sum))
        }
        return result
    }

    /// Audio thread. The level comes from the first channel.
    private func append(_ input: AVAudioPCMBuffer) {
        let buffer = Self.mono(input)
        var rms: Float = 0
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                sum += samples[index] * samples[index]
            }
            rms = (sum / Float(buffer.frameLength)).squareRoot()
        }
        lock.lock()
        request?.append(buffer)
        peak = max(peak, rms)
        let writer = writer
        lock.unlock()
        // Converting is the slow part, so it happens outside the lock; the writer guards itself.
        writer?.append(buffer)
    }
}
