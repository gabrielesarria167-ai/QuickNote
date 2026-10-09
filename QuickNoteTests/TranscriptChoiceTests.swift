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
}
