import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Why a recording couldn't start or had to stop. The messages are shown in the recording pill.
enum VoiceRecorderError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case noInputDevice
    /// Recording the Mac's own audio failed to start, usually because that permission is off.
    case systemAudioUnavailable
    /// The microphone went away or changed during the recording.
    case inputLost
    /// The recognizer failed again and again. What was heard before is saved.
    case recognitionStopped
    /// Like `recognitionStopped`, shown instead when nothing at all was heard.
    case recognitionNotWorking

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Allow microphone access under System Settings → Privacy & Security → Microphone."
        case .speechDenied:
            "Allow speech recognition under System Settings → Privacy & Security → Speech Recognition."
        case .recognizerUnavailable:
            "Speech recognition isn't available for your language right now."
        case .noInputDevice:
            "No microphone could be opened. Check that one is connected."
        case .systemAudioUnavailable:
            "Allow QuickNote under System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, or turn off \"Record the Mac's audio\" in Settings."
        case .inputLost:
            "The microphone stopped working. What was said so far has been saved."
        case .recognitionStopped:
            "Speech recognition stopped working. What was heard so far has been saved."
        case .recognitionNotWorking:
            "Speech recognition isn't working right now. Check Siri & Dictation in System Settings, and your internet connection."
        }
    }

    /// Where to turn the missing permission on, for the errors that are about one.
    var settingsURL: URL? {
        switch self {
        case .microphoneDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .systemAudioUnavailable:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        default:
            nil
        }
    }
}

/// Asks for the permissions a recording needs. The system calls back on its own queues, so these are
/// nonisolated: a main-actor closure running elsewhere would trap under Swift 6.
enum SpeechPermissions {
    /// True if the microphone may be used, asking the first time.
    nonisolated static func microphone() async -> Bool {
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

    /// True if speech recognition may be used, asking the first time.
    nonisolated static func speech() async -> Bool {
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
}
