import Foundation
import NaturalLanguage

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

    /// Gemini's transcript counts as cut short when it has fewer than this share of the words Apple heard.
    static let shortShare = 0.6

    /// Apple's text must have at least this many words before the comparison means anything.
    static let minimumWordsToCompare = 20

    /// The number of words in `text`. Uses the system's word tokenizer, since whitespace doesn't
    /// separate words in Chinese, Japanese or Thai.
    static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    /// How sure the recognizer must be of each text's language before a difference counts. Short
    /// strings are misdetected otherwise ("OK so" comes back as German at 0.61).
    static let languageConfidence = 0.9

    /// Whether the two texts are clearly in different languages. If either language can't be told with
    /// high confidence, they are assumed to match.
    static func languagesDiffer(_ first: String, _ second: String) -> Bool {
        guard let a = confidentLanguage(first), let b = confidentLanguage(second) else { return false }
        return a != b
    }

    private static func confidentLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value >= languageConfidence else {
            return nil
        }
        return best.key
    }

    /// Whether `gemini`'s transcript looks cut short next to what Apple's live recognizer heard of the
    /// same recording: Apple's text is long enough to compare and Gemini has under 60% of its words.
    /// Texts in different languages can't be compared by word count, so they never look cut short.
    static func looksCutShort(gemini: String, apple: String) -> Bool {
        let appleWords = wordCount(apple)
        guard appleWords >= minimumWordsToCompare, !languagesDiffer(gemini, apple) else { return false }
        return Double(wordCount(gemini)) < Double(appleWords) * shortShare
    }

    /// Of two answers to the same recording, the one with more words (the first on a tie).
    static func longer(_ first: Transcription, _ second: Transcription) -> Transcription {
        wordCount(second.transcript) > wordCount(first.transcript) ? second : first
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
