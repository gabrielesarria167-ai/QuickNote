import Testing
@testable import QuickNote

struct NoteTextTests {
    @Test func appendingToBlankTextGivesTheParagraph() {
        #expect("".appendingParagraph("hello") == "hello")
        #expect(" \n ".appendingParagraph("hello") == "hello")
    }

    @Test func appendingStartsANewParagraph() {
        #expect("hello".appendingParagraph("world") == "hello\n\nworld")
    }

    @Test func appendingDropsTrailingWhitespaceOfExistingText() {
        #expect("hello\n".appendingParagraph("world") == "hello\n\nworld")
        #expect("hello \n\n  ".appendingParagraph("world") == "hello\n\nworld")
    }

    @Test func appendingTrimsTheParagraph() {
        #expect("hello".appendingParagraph("  world \n") == "hello\n\nworld")
    }

    @Test func blankParagraphLeavesExistingTextUnchanged() {
        #expect("hello\n".appendingParagraph("") == "hello\n")
        #expect("hello".appendingParagraph("  \n") == "hello")
        #expect("".appendingParagraph(" ") == "")
    }
}
