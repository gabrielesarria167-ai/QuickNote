import Testing
@testable import QuickNote

struct VoiceNoteTextTests {
    @Test func missingOrBlankTitleGivesNil() {
        #expect(VoiceNoteText.sanitizeTitle(nil) == nil)
        #expect(VoiceNoteText.sanitizeTitle("") == nil)
        #expect(VoiceNoteText.sanitizeTitle(" \n \t ") == nil)
        #expect(VoiceNoteText.sanitizeTitle("# ") == nil)
        #expect(VoiceNoteText.sanitizeTitle("\"\"") == nil)
    }

    @Test func onlyTheFirstNonBlankLineIsKept() {
        #expect(VoiceNoteText.sanitizeTitle("Trip plan\nand more") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("\n  \nTrip plan\n") == "Trip plan")
    }

    @Test func whitespaceInsideIsCollapsed() {
        #expect(VoiceNoteText.sanitizeTitle("  Trip \t  plan  ") == "Trip plan")
    }

    @Test func aTitleMarkIsRemoved() {
        #expect(VoiceNoteText.sanitizeTitle("# Already") == "Already")
        #expect(VoiceNoteText.sanitizeTitle("### Already") == "Already")
        #expect(VoiceNoteText.sanitizeTitle("###### Already") == "Already")
    }

    @Test func bulletsTodosAndQuotesAtTheStartAreRemoved() {
        #expect(VoiceNoteText.sanitizeTitle("- Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("* Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("• Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("[ ] Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("[x] Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("- [ ] Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("> Buy milk") == "Buy milk")
        #expect(VoiceNoteText.sanitizeTitle("> # - Buy milk") == "Buy milk")
    }

    @Test func aWordThatMerelyStartsWithAMarkCharacterIsKept() {
        #expect(VoiceNoteText.sanitizeTitle("#hashtag ideas") == "#hashtag ideas")
        #expect(VoiceNoteText.sanitizeTitle("-5 degrees") == "-5 degrees")
    }

    @Test func surroundingQuotesAndTheTrailingPeriodAreRemoved() {
        #expect(VoiceNoteText.sanitizeTitle("\"Trip plan\"") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("“Trip plan”") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("Trip plan.") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("Trip plan...") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("Piano di viaggio。") == "Piano di viaggio")
        #expect(VoiceNoteText.sanitizeTitle("\"Trip plan.\"") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("\"Trip plan\".") == "Trip plan")
    }

    @Test func otherPunctuationAndInnerQuotesStay() {
        #expect(VoiceNoteText.sanitizeTitle("Why not?") == "Why not?")
        #expect(VoiceNoteText.sanitizeTitle("Dogs' day out") == "Dogs' day out")
        #expect(VoiceNoteText.sanitizeTitle("Version 1.2 notes") == "Version 1.2 notes")
    }

    @Test func inlineMarksAreRemoved() {
        #expect(VoiceNoteText.sanitizeTitle("**Bold** and _italic_") == "Bold and italic")
        #expect(VoiceNoteText.sanitizeTitle("~~Old~~ ==new== title") == "Old new title")
        #expect(VoiceNoteText.sanitizeTitle("**Trip plan.**") == "Trip plan")
        #expect(VoiceNoteText.sanitizeTitle("# **Trip plan**") == "Trip plan")
    }

    @Test func aShortTitleIsNotCut() {
        let title = String(repeating: "a", count: VoiceNoteText.maxTitleLength)
        #expect(VoiceNoteText.sanitizeTitle(title) == title)
    }

    @Test func aLongTitleIsCutAtAWordBoundary() throws {
        let long = Array(repeating: "wordy", count: 30).joined(separator: " ")
        let title = try #require(VoiceNoteText.sanitizeTitle(long))
        #expect(title.count <= VoiceNoteText.maxTitleLength)
        #expect(title.count > VoiceNoteText.maxTitleLength - 6)
        #expect(title.split(separator: " ").allSatisfy { $0 == "wordy" })
    }

    @Test func aCutAtTheEndOfAWordKeepsTheWholeWord() {
        let first = String(repeating: "a", count: VoiceNoteText.maxTitleLength)
        #expect(VoiceNoteText.sanitizeTitle(first + " more") == first)
    }

    @Test func aLongTitleWithoutSpacesIsCutHard() {
        let title = VoiceNoteText.sanitizeTitle(String(repeating: "日", count: 200))
        #expect(title == String(repeating: "日", count: VoiceNoteText.maxTitleLength))
    }

    @Test func aCutDoesNotLeaveDanglingPunctuation() {
        let text = String(repeating: "a", count: 76) + " -, and then some"
        #expect(VoiceNoteText.sanitizeTitle(text) == String(repeating: "a", count: 76))
    }

    @Test func composeWritesTheTitleAboveTheTranscript() {
        #expect(VoiceNoteText.compose(title: "Trip plan", transcript: "Buy tickets.") == "# Trip plan\nBuy tickets.")
    }

    @Test func composeCleansTheTitle() {
        #expect(VoiceNoteText.compose(title: "# \"Trip plan.\"", transcript: "Buy tickets.") == "# Trip plan\nBuy tickets.")
    }

    @Test func composeWithoutAUsableTitleGivesTheTranscript() {
        #expect(VoiceNoteText.compose(title: nil, transcript: " Buy tickets.\n") == "Buy tickets.")
        #expect(VoiceNoteText.compose(title: "  ", transcript: "Buy tickets.") == "Buy tickets.")
    }

    @Test func composeWithABlankTranscriptGivesNothing() {
        #expect(VoiceNoteText.compose(title: "Trip plan", transcript: " \n") == "")
        #expect(VoiceNoteText.compose(title: nil, transcript: "") == "")
    }

    @Test func composedTextStartsWithATitleLineThenText() {
        let text = VoiceNoteText.compose(title: "Trip plan", transcript: "Buy tickets.\n\nPack bags.")
        let kinds = MarkdownParser.lines(in: text).map(\.kind)
        #expect(kinds == [.title, .text, .text, .text])
    }

    @Test func composedTextWithoutATitleHasNoTitleLine() {
        let text = VoiceNoteText.compose(title: nil, transcript: "Buy tickets.")
        #expect(MarkdownParser.lines(in: text).map(\.kind) == [.text])
    }

    @Test func composedTextIsAppendedAsOneParagraph() {
        let composed = VoiceNoteText.compose(title: "T", transcript: "body")
        #expect("existing".appendingParagraph(composed) == "existing\n\n# T\nbody")
        #expect("".appendingParagraph(composed) == "# T\nbody")
    }
}
