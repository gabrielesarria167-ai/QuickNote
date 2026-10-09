import Testing
@testable import QuickNote

struct TranscriptExcerptTests {
    @Test func shortTextIsUnchanged() {
        #expect("hello world".endingExcerpt(maxLength: 20) == "hello world")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect("  hello \n".endingExcerpt(maxLength: 20) == "hello")
    }

    @Test func longTextKeepsTheEndCutAtAWordBoundary() {
        let text = "one two three four five six seven"
        let excerpt = text.endingExcerpt(maxLength: 18)
        #expect(excerpt == "… five six seven")
        #expect(text.hasSuffix(excerpt.dropFirst(2)))
    }

    @Test func aCutExactlyBetweenWordsKeepsTheWholeWord() {
        #expect("aaa bbb ccc".endingExcerpt(maxLength: 7) == "… bbb ccc")
    }

    @Test func aSingleHugeWordIsKeptAsItsEnd() {
        #expect("abcdefghij".endingExcerpt(maxLength: 4) == "… ghij")
    }

    @Test func excerptIsNeverMuchLongerThanTheLimit() {
        let text = String(repeating: "word ", count: 100)
        #expect(text.endingExcerpt(maxLength: 90).count <= 92)
    }
}
