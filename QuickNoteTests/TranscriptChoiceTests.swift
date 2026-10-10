import Testing
@testable import QuickNote

struct TranscriptChoiceTests {
    @Test func geminiIsUsedWhenItSucceeded() {
        let choice = TranscriptChoice.choose(
            gemini: .success(Transcription(title: "Trip plan", transcript: "Buy tickets.")),
            apple: "by tickets"
        )
        #expect(choice.title == "Trip plan")
        #expect(choice.text == "Buy tickets.")
        #expect(choice.notice == nil)
    }

    @Test func geminisTitleIsCleaned() {
        let choice = TranscriptChoice.choose(
            gemini: .success(Transcription(title: "# \"Trip plan.\"", transcript: "Buy tickets.")),
            apple: "by tickets"
        )
        #expect(choice.title == "Trip plan")
    }

    @Test func aBlankTitleIsNil() {
        let choice = TranscriptChoice.choose(
            gemini: .success(Transcription(title: " ", transcript: "Buy tickets.")),
            apple: "by tickets"
        )
        #expect(choice.title == nil)
        #expect(choice.text == "Buy tickets.")
        #expect(choice.notice == nil)
    }

    @Test func appleTextIsUsedWithoutATitleWhenGeminiFailed() {
        for error in [GeminiError.badKey, .quota, .server, .blocked, .truncated, .malformed, .empty, .tooLarge, .offline] {
            let choice = TranscriptChoice.choose(gemini: .failure(error), apple: "  by tickets \n")
            #expect(choice.title == nil)
            #expect(choice.text == "by tickets")
            #expect(choice.notice == error)
        }
    }

    @Test func appleTextIsUsedQuietlyWhenGeminiWasNotAsked() {
        let choice = TranscriptChoice.choose(gemini: nil, apple: "by tickets")
        #expect(choice.title == nil)
        #expect(choice.text == "by tickets")
        #expect(choice.notice == nil)
    }

    @Test func aSuccessWithoutTextFallsBackToApple() {
        let choice = TranscriptChoice.choose(gemini: .success(Transcription(title: "x", transcript: " ")), apple: "by tickets")
        #expect(choice.title == nil)
        #expect(choice.text == "by tickets")
        #expect(choice.notice == .empty)
    }

    @Test func nothingFromEitherGivesEmptyText() {
        #expect(TranscriptChoice.choose(gemini: .failure(.empty), apple: " ").text == "")
        #expect(TranscriptChoice.choose(gemini: nil, apple: "").text == "")
    }

    @Test func geminiIsAskedOnlyWithAudioOfSomeLengthAndAKey() {
        #expect(TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 3, hasKey: true))
        #expect(TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 0.5, hasKey: true))
        #expect(!TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 0.49, hasKey: true))
        #expect(!TranscriptChoice.shouldTranscribe(hasAudio: false, duration: 3, hasKey: true))
        #expect(!TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 3, hasKey: false))
    }

    private func words(_ count: Int) -> String {
        let pool = ["we", "should", "meet", "tomorrow", "morning", "to", "talk", "about", "the", "plan", "for", "our", "trip", "and", "book", "tickets"]
        return (0..<count).map { pool[$0 % pool.count] }.joined(separator: " ")
    }

    private let english = "I think we should meet tomorrow morning to talk about the plan for the trip, " +
        "and then book the tickets, the hotel and the car before the prices go up again next week."

    @Test func aTextInAnotherLanguageIsNotComparedByWordCount() {
        #expect(TranscriptChoice.wordCount(english) >= 20)
        #expect(!TranscriptChoice.looksCutShort(gemini: "明日の朝に会って、旅行の計画について話しましょう。", apple: english))
        #expect(!TranscriptChoice.looksCutShort(gemini: "我们明天早上见面，谈谈旅行的计划。", apple: english))
    }

    @Test func chineseAndJapaneseWordsAreCountedWithoutSpaces() {
        #expect(TranscriptChoice.wordCount("明日の朝に会って旅行の計画について話しましょう") > 3)
        #expect(TranscriptChoice.wordCount("我们明天早上见面谈谈旅行的计划") > 3)
    }

    @Test func aTooShortTextIsNotTakenForAnotherLanguage() {
        #expect(TranscriptChoice.wordCount(english) >= 20)
        #expect(TranscriptChoice.looksCutShort(gemini: "OK so", apple: english))
    }

    @Test func aCutShortTextInTheSameLanguageIsStillCaught() {
        #expect(TranscriptChoice.looksCutShort(gemini: "I think we should meet tomorrow morning.", apple: english))
    }

    @Test func wordsAreCountedOnWhitespace() {
        #expect(TranscriptChoice.wordCount("") == 0)
        #expect(TranscriptChoice.wordCount("  one two\nthree\t four ") == 4)
    }

    @Test func aTranscriptUnderSixtyPercentOfApplesLooksCutShort() {
        #expect(TranscriptChoice.looksCutShort(gemini: words(11), apple: words(20)))
        #expect(!TranscriptChoice.looksCutShort(gemini: words(12), apple: words(20)))
        #expect(!TranscriptChoice.looksCutShort(gemini: words(100), apple: words(20)))
    }

    @Test func aShortAppleTextIsNotComparedWith() {
        #expect(!TranscriptChoice.looksCutShort(gemini: "", apple: words(19)))
        #expect(!TranscriptChoice.looksCutShort(gemini: "", apple: ""))
        #expect(TranscriptChoice.looksCutShort(gemini: "", apple: words(20)))
    }

    @Test func theLongerAnswerWins() {
        let short = Transcription(title: "a", transcript: words(3))
        let long = Transcription(title: "b", transcript: words(9))
        #expect(TranscriptChoice.longer(short, long) == long)
        #expect(TranscriptChoice.longer(long, short) == long)
        let tie = Transcription(title: "c", transcript: words(3))
        #expect(TranscriptChoice.longer(short, tie) == short)
    }
}
