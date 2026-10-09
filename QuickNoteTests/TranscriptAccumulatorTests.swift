import Testing
@testable import QuickNote

struct TranscriptAccumulatorTests {
    private var accumulator = TranscriptAccumulator()

    @Test mutating func startsEmpty() {
        #expect(accumulator.isEmpty)
        #expect(accumulator.text == "")
    }

    @Test mutating func laterPartialReplacesEarlierOne() {
        accumulator.update(partial: "hello")
        accumulator.update(partial: "hello world")
        #expect(accumulator.text == "hello world")
        #expect(!accumulator.isEmpty)
    }

    @Test mutating func newPartialJoinsCommittedSegmentWithASpace() {
        accumulator.update(partial: "first part")
        accumulator.commitSegment()
        accumulator.update(partial: "second part")
        #expect(accumulator.text == "first part second part")
    }

    @Test mutating func multipleSegmentsAreJoined() {
        for words in ["one two.", "three four.", "five."] {
            accumulator.update(partial: words)
            accumulator.commitSegment()
        }
        #expect(accumulator.text == "one two. three four. five.")
    }

    @Test mutating func commitClearsThePartial() {
        accumulator.update(partial: "hello")
        accumulator.commitSegment()
        accumulator.commitSegment()
        #expect(accumulator.text == "hello")
    }

    @Test mutating func commitWithFinalUsesTheFinalText() {
        accumulator.update(partial: "hello wor")
        accumulator.commitSegment(final: "hello world.")
        #expect(accumulator.text == "hello world.")
    }

    @Test mutating func emptyOrWhitespaceCommitIsIgnored() {
        accumulator.update(partial: "kept")
        accumulator.commitSegment()
        accumulator.update(partial: "  \n ")
        accumulator.commitSegment()
        accumulator.commitSegment(final: "   ")
        #expect(accumulator.text == "kept")
    }

    @Test mutating func segmentsAreTrimmed() {
        accumulator.update(partial: "  padded \n")
        accumulator.commitSegment()
        accumulator.update(partial: " more ")
        #expect(accumulator.text == "padded more")
    }

    @Test mutating func whitespaceOnlyPartialCountsAsEmpty() {
        accumulator.update(partial: "   ")
        #expect(accumulator.isEmpty)
    }

    @Test func appendingToBlankTextGivesTheTranscript() {
        #expect(TranscriptAccumulator.appending("hello", to: "") == "hello")
        #expect(TranscriptAccumulator.appending("hello", to: " \n ") == "hello")
    }

    @Test func appendingStartsANewParagraph() {
        #expect(TranscriptAccumulator.appending("world", to: "hello") == "hello\n\nworld")
    }

    @Test func appendingDropsTrailingWhitespaceOfExistingText() {
        #expect(TranscriptAccumulator.appending("world", to: "hello\n") == "hello\n\nworld")
        #expect(TranscriptAccumulator.appending("world", to: "hello \n\n  ") == "hello\n\nworld")
    }

    @Test func appendingTrimsTheTranscript() {
        #expect(TranscriptAccumulator.appending("  world \n", to: "hello") == "hello\n\nworld")
    }

    @Test func blankTranscriptLeavesExistingTextUnchanged() {
        #expect(TranscriptAccumulator.appending("", to: "hello\n") == "hello\n")
        #expect(TranscriptAccumulator.appending("  \n", to: "hello") == "hello")
        #expect(TranscriptAccumulator.appending(" ", to: "") == "")
    }
}
