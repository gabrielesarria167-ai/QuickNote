import Foundation

/// Why a recording was kept on disk instead of being deleted after use.
enum KeptReason: Equatable {
    /// Gemini failed.
    case gemini(GeminiError)
    /// The key couldn't be read from the Keychain.
    case keyUnreadable
    /// The user stopped waiting for Gemini and chose to keep the recording.
    case stoppedWaiting
    /// Gemini answered, but its transcript has far fewer words than Apple heard, so the end may be missing.
    case incomplete
}

/// What the recording pill says when Gemini's answer wasn't used.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum GeminiNotice {
    /// The message for `error` when the recording was not kept (Gemini heard nothing). `savedOnDevice`
    /// says whether Apple's text was saved instead; if there was none, nothing was saved and the
    /// message doesn't claim it.
    static func message(for error: GeminiError, savedOnDevice: Bool = true) -> String {
        let reason = switch error {
        case .badKey: "Gemini didn't accept the API key"
        case .badModel: "Gemini doesn't know this model"
        case .offline: "No connection"
        case .mismatch: "Gemini's text didn't match what was said"
        case .quota: "Gemini quota reached"
        case .server, .blocked, .truncated, .malformed, .empty, .tooLarge: "Gemini couldn't transcribe this"
        }
        return savedOnDevice ? "\(reason) — saved the on-device text." : "\(reason)."
    }

    /// The message when the recording was kept. It always says so, even if no text was saved, unless
    /// moving it to the Unsent Recordings folder failed (`recordingKept` false): then it says that.
    static func keptMessage(for reason: KeptReason, savedOnDevice: Bool, recordingKept: Bool = true) -> String {
        let outcome = recordingKept ? "recording kept" : "the recording couldn't be kept"
        let message = switch reason {
        case .gemini(let error): "Gemini couldn't transcribe — \(outcome). \(short(error))"
        case .keyUnreadable: "Couldn't read the Gemini key from the Keychain — \(outcome)."
        case .stoppedWaiting: "Stopped waiting for Gemini — \(outcome)."
        case .incomplete: "Gemini's transcript may be missing the end — \(outcome)."
        }
        // Gemini's own text was saved for `.incomplete`, so there is no on-device text to mention.
        return savedOnDevice && reason != .incomplete ? message + " On-device text saved." : message
    }

    private static func short(_ error: GeminiError) -> String {
        switch error {
        case .badKey: "The API key wasn't accepted."
        case .badModel: "The model wasn't found."
        case .quota: "Quota reached."
        case .offline: "No connection."
        case .server: "Google's server had a problem."
        case .blocked: "Gemini declined to answer."
        case .truncated: "The answer was cut off."
        case .malformed: "The answer wasn't usable."
        case .tooLarge: "The recording is too big to send."
        case .empty: "No speech was found."
        case .mismatch: "Its text didn't match what was said."
        }
    }

    /// Whether the pill offers to open the Settings window, where the key and model are.
    static func offersSettings(for error: GeminiError) -> Bool {
        error == .badKey || error == .badModel
    }

    static func offersSettings(for reason: KeptReason) -> Bool {
        if case .gemini(let error) = reason { return offersSettings(for: error) }
        return false
    }
}
