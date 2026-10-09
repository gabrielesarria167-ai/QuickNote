import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Hands microphone buffers from the audio thread to whichever recognition request is current, and
/// the loudest level heard since the last time it was asked for. Everything is behind one lock.
final class RequestBox: @unchecked Sendable {
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

    /// Audio thread. The level comes from the first channel.
    private func append(_ buffer: AVAudioPCMBuffer) {
        var rms: Float = 0
        if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                sum += samples[index] * samples[index]
            }
            rms = (sum / Float(buffer.frameLength)).squareRoot()
        }
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
        peak = max(peak, rms)
    }
}
