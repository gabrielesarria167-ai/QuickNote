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
        words(text).count
    }

    /// The words of `text`, without punctuation, case, accents or apostrophes, so that "Doesn’t",
    /// "doesn't" and "doesnt" are the same word, and so are "página" and "pagina".
    static func words(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            var word = text[range].folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            word.removeAll { "'’‘ʼ".contains($0) }
            if !word.isEmpty { words.append(word) }
            return true
        }
        return words
    }

    /// Gemini's transcript counts as unrelated when fewer than this share of its three-word phrases
    /// (or of Apple's, whichever text has fewer) also appear in the other text. Single words are no
    /// use: "the", "is" and "my" turn up in any long recording. Two transcripts of the same speech share
    /// most phrases even when Apple misheard a word in five.
    static let sharedPhrases = 0.15

    /// The distinct runs of three consecutive words in `text`.
    static func phrases(_ text: String) -> Set<String> {
        let words = words(text)
        guard words.count >= 3 else { return [] }
        return Set((0...(words.count - 3)).map { words[$0..<($0 + 3)].joined(separator: " ") })
    }

    /// Whether `gemini`'s transcript looks like it is about something else than what Apple's recognizer
    /// heard of the same recording: Gemini sometimes answers with invented text ("Hello, my name is
    /// John…") instead of the audio. Needs as much of Apple's text as `looksCutShort`, and both texts
    /// clearly in the same language (`languagesMatch`); otherwise it can't tell and says no, since a
    /// real transcript must never be thrown away for not matching what a recognizer in the wrong
    /// language heard. A transcript that is only short is not unrelated: the share is of the shorter
    /// text's phrases.
    static func looksUnrelated(gemini: String, apple: String) -> Bool {
        guard wordCount(apple) >= minimumWordsToCompare, languagesMatch(gemini, apple) else { return false }
        let ours = phrases(gemini)
        let theirs = phrases(apple)
        guard !ours.isEmpty, !theirs.isEmpty else { return false }
        let shared = ours.intersection(theirs).count
        return Double(shared) < Double(min(ours.count, theirs.count)) * sharedPhrases
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

    /// Whether both texts are, with high confidence, in the same language. Stricter than
    /// `!languagesDiffer`: Apple's recognizer set to English turns Spanish speech into a mix of English
    /// and Spanish-looking words that may be told as either, and such a text can't be compared.
    static func languagesMatch(_ first: String, _ second: String) -> Bool {
        guard let a = confidentLanguage(first), let b = confidentLanguage(second) else { return false }
        return a == b
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

    /// Of two answers to the same recording, the one that matches what Apple heard, or the longer if
    /// both do or neither does. More words alone would prefer an invented text to a real one.
    static func better(_ first: Transcription, _ second: Transcription, apple: String) -> Transcription {
        let firstUnrelated = looksUnrelated(gemini: first.transcript, apple: apple)
        let secondUnrelated = looksUnrelated(gemini: second.transcript, apple: apple)
        if firstUnrelated != secondUnrelated { return firstUnrelated ? second : first }
        return longer(first, second)
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
