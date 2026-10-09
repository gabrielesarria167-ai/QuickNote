import Testing
@testable import QuickNote

struct SegmentedTranscriptTests {
    private var transcript = SegmentedTranscript()

    @Test func startsEmpty() {
        #expect(transcript.text == "")
        #expect(!transcript.hasPending)
    }

    @Test mutating func laterPartialReplacesEarlierOne() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "hello", startsAt: 0.2, endsAt: nil, isLast: false)
        transcript.receive(generation: 0, text: "hello world", startsAt: 0.2, endsAt: nil, isLast: false)
        #expect(transcript.text == "hello world")
        #expect(transcript.hasPending)
    }

    @Test mutating func finishedSegmentsAreJoinedWithASpace() {
        for (generation, words) in ["one two.", "three four.", "five."].enumerated() {
            transcript.begin(generation: generation)
            transcript.receive(generation: generation, text: words, startsAt: 0, endsAt: nil, isLast: true)
        }
        #expect(transcript.text == "one two. three four. five.")
        #expect(!transcript.hasPending)
    }

    @Test mutating func closingTheCurrentSegmentIsReported() {
        transcript.begin(generation: 0)
        var closed = transcript.receive(generation: 0, text: "hello", startsAt: 0, endsAt: nil, isLast: false)
        #expect(!closed)
        closed = transcript.receive(generation: 0, text: "hello.", startsAt: 0, endsAt: nil, isLast: true)
        #expect(closed)
    }

    @Test mutating func closingAnOldSegmentIsNotReported() {
        transcript.begin(generation: 0)
        transcript.begin(generation: 1)
        var closed = transcript.receive(generation: 0, text: "old", startsAt: 0, endsAt: nil, isLast: true)
        #expect(!closed)
        closed = transcript.receive(generation: 1, text: "new", startsAt: 0, endsAt: nil, isLast: true)
        #expect(closed)
    }

    @Test mutating func aSegmentHandedOverKeepsUpdatingUntilItIsFinal() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "hello wor", startsAt: 0, endsAt: nil, isLast: false)
        transcript.begin(generation: 1)
        transcript.receive(generation: 1, text: "again", startsAt: 0, endsAt: nil, isLast: false)
        transcript.receive(generation: 0, text: "hello world", startsAt: 0, endsAt: nil, isLast: false)
        #expect(transcript.text == "hello world again")
    }

    @Test mutating func finishedSegmentWaitsBehindAnUnfinishedOne() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "hello wor", startsAt: 0, endsAt: nil, isLast: false)
        transcript.begin(generation: 1)
        transcript.receive(generation: 1, text: "again.", startsAt: 0, endsAt: nil, isLast: true)
        #expect(transcript.text == "hello wor again.")
        #expect(transcript.hasPending)
    }

    @Test mutating func finalsInTheWrongOrderKeepSpeechOrder() {
        transcript.begin(generation: 0)
        transcript.begin(generation: 1)
        transcript.receive(generation: 1, text: "second.", startsAt: 0, endsAt: nil, isLast: true)
        transcript.receive(generation: 0, text: "first.", startsAt: 0, endsAt: nil, isLast: true)
        #expect(transcript.text == "first. second.")
        #expect(!transcript.hasPending)
    }

    @Test mutating func unknownGenerationIsIgnored() {
        transcript.begin(generation: 3)
        let closed = transcript.receive(generation: 7, text: "stray", startsAt: 0, endsAt: nil, isLast: true)
        #expect(!closed)
        #expect(transcript.text == "")
        #expect(transcript.hasPending)
    }

    @Test mutating func resultsAfterTheLastOneAreIgnored() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "done.", startsAt: 0, endsAt: nil, isLast: true)
        let closed = transcript.receive(generation: 0, text: "late partial", startsAt: 0, endsAt: nil, isLast: false)
        #expect(!closed)
        #expect(transcript.text == "done.")
    }

    @Test mutating func emptyResultNeverOverwritesHeardText() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "kept", startsAt: 0, endsAt: nil, isLast: false)
        transcript.receive(generation: 0, text: "", startsAt: nil, endsAt: nil, isLast: false)
        transcript.receive(generation: 0, text: nil, startsAt: nil, endsAt: nil, isLast: false)
        transcript.receive(generation: 0, text: "  ", startsAt: nil, endsAt: nil, isLast: true)
        #expect(transcript.text == "kept")
        #expect(!transcript.hasPending)
    }

    @Test mutating func failureKeepsTheLastPartial() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "half a sentence", startsAt: 0, endsAt: nil, isLast: false)
        transcript.receive(generation: 0, text: nil, startsAt: nil, endsAt: nil, isLast: true)
        #expect(transcript.text == "half a sentence")
        #expect(transcript.lastEndedHeardText)
    }

    @Test mutating func endedSegmentWithoutTextIsReported() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: nil, startsAt: nil, endsAt: nil, isLast: true)
        #expect(!transcript.lastEndedHeardText)
        #expect(transcript.text == "")
    }

    @Test mutating func reviseWordsWithoutRestartingDoesNotRepeatThem() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "recognize speech", startsAt: 0.4, endsAt: 1.5, isLast: false)
        transcript.receive(generation: 0, text: "wreck a nice beach", startsAt: 0.4, endsAt: 2.0, isLast: false)
        transcript.receive(generation: 0, text: "wreck a nice beach today", startsAt: 0.5, endsAt: 2.6, isLast: true)
        #expect(transcript.text == "wreck a nice beach today")
    }

    @Test mutating func aSpuriousFirstWordRevisedAwayIsNotTakenForARestart() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "Uh hello", startsAt: 0.2, endsAt: 1.0, isLast: false)
        // The first word is dropped, so the first word now starts later, but before the old end.
        transcript.receive(generation: 0, text: "Hello there", startsAt: 0.9, endsAt: 1.6, isLast: false)
        #expect(transcript.text == "Hello there")
    }

    @Test mutating func zeroTimestampsNeverTriggerARestart() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "first sentence.", startsAt: 0.3, endsAt: 2.0, isLast: false)
        transcript.receive(generation: 0, text: "first sentence. and more", startsAt: 0, endsAt: 0, isLast: false)
        #expect(transcript.text == "first sentence. and more")
        transcript.receive(generation: 0, text: "different", startsAt: 5, endsAt: 0, isLast: false)
        #expect(transcript.text == "different")
    }

    @Test mutating func zeroTimestampsEarlierDoNotMakeALaterStartARestart() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "one", startsAt: 0, endsAt: 0, isLast: false)
        transcript.receive(generation: 0, text: "one two", startsAt: 0.3, endsAt: 1.0, isLast: false)
        #expect(transcript.text == "one two")
    }

    @Test mutating func textDroppedAfterAPauseIsKept() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "first sentence.", startsAt: 0.3, endsAt: 2.0, isLast: false)
        // After a pause the recognizer starts over with only the new words, starting 6 s in.
        transcript.receive(generation: 0, text: "second", startsAt: 6.1, endsAt: 6.6, isLast: false)
        transcript.receive(generation: 0, text: "second sentence.", startsAt: 6.1, endsAt: 7.4, isLast: false)
        #expect(transcript.text == "first sentence. second sentence.")
        transcript.receive(generation: 0, text: "second sentence.", startsAt: 6.1, endsAt: 7.4, isLast: true)
        #expect(transcript.text == "first sentence. second sentence.")
    }

    @Test mutating func severalPausesKeepEverything() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "one", startsAt: 0.2, endsAt: 0.6, isLast: false)
        transcript.receive(generation: 0, text: "two", startsAt: 3.0, endsAt: 3.4, isLast: false)
        transcript.receive(generation: 0, text: "three", startsAt: 7.0, endsAt: 7.5, isLast: false)
        #expect(transcript.text == "one two three")
    }

    @Test mutating func recognizerGivingTheWholeSegmentAgainDoesNotRepeatIt() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "first sentence.", startsAt: 0.3, endsAt: 2.0, isLast: false)
        transcript.receive(generation: 0, text: "second", startsAt: 6.1, endsAt: 6.6, isLast: false)
        // The final result contains everything again, from the start.
        transcript.receive(generation: 0, text: "First sentence, second sentence.", startsAt: 0.3, endsAt: 7.4, isLast: true)
        #expect(transcript.text == "First sentence, second sentence.")
    }

    @Test mutating func resendWithoutUsableTimestampsDoesNotRepeatEither() {
        transcript.begin(generation: 0)
        transcript.receive(generation: 0, text: "first sentence.", startsAt: 0.3, endsAt: 2.0, isLast: false)
        transcript.receive(generation: 0, text: "second", startsAt: 6.1, endsAt: 6.6, isLast: false)
        transcript.receive(generation: 0, text: "first sentence. second sentence.", startsAt: 0, endsAt: 0, isLast: true)
        #expect(transcript.text == "first sentence. second sentence.")
    }
}
