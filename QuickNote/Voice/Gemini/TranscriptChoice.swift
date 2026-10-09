import Foundation

/// Decides which transcript a voice note is saved with: Gemini's when it worked, otherwise the text
/// Apple's on-device recognizer heard.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum TranscriptChoice {
    /// Recordings shorter than this (in seconds) aren't sent to Gemini: there is nothing worth the trip.
    static let minimumAudioDuration: TimeInterval = 0.5

    /// Whether to ask Gemini: there is audio, it is long enough and there is a key.
    static func shouldTranscribe(hasAudio: Bool, duration: TimeInterval, hasKey: Bool) -> Bool {
        hasAudio && hasKey && duration >= minimumAudioDuration
    }

    /// `gemini` is nil when Gemini wasn't asked (no key, or the user chose the on-device text). The
    /// title is nil without Gemini. `notice` is why Gemini's answer wasn't used, if it was asked.
    static func choose(
        gemini: Result<Transcription, GeminiError>?,
        apple: String
    ) -> (title: String?, text: String, notice: GeminiError?) {
        let apple = apple.trimmingCharacters(in: .whitespacesAndNewlines)
        switch gemini {
        case nil:
            return (nil, apple, nil)
        case .success(let transcription):
            let text = transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return (nil, apple, .empty) }
            return (VoiceNoteText.sanitizeTitle(transcription.title), text, nil)
        case .failure(let error):
            return (nil, apple, error)
        }
    }
}
