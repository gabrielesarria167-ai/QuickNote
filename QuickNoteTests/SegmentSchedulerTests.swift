import Testing
@testable import QuickNote

struct SegmentSchedulerTests {
    private var scheduler = SegmentScheduler()

    private mutating func begin() {
        scheduler.begin(at: 1000)
    }

    @Test mutating func nothingHappensEarly() {
        begin()
        var action = scheduler.tick(at: 1010, loudness: 0)
        #expect(action == .none)
        action = scheduler.tick(at: 1044, loudness: 0)
        #expect(action == .none)
    }

    @Test mutating func rotatesAtAPauseAfter45Seconds() {
        begin()
        var action = scheduler.tick(at: 1045.0, loudness: 0.8)
        #expect(action == .none)
        action = scheduler.tick(at: 1045.1, loudness: 0.0)
        #expect(action == .none)
        action = scheduler.tick(at: 1045.2, loudness: 0.0)
        #expect(action == .none)
        action = scheduler.tick(at: 1045.4, loudness: 0.0)
        #expect(action == .rotate)
    }

    @Test mutating func aBriefQuietMomentIsNotAPause() {
        begin()
        var action = scheduler.tick(at: 1046.0, loudness: 0.0)
        #expect(action == .none)
        action = scheduler.tick(at: 1046.1, loudness: 0.7)
        #expect(action == .none)
        action = scheduler.tick(at: 1046.2, loudness: 0.0)
        #expect(action == .none)
        action = scheduler.tick(at: 1046.4, loudness: 0.0)
        #expect(action == .none)
    }

    @Test mutating func keepsWaitingForAPauseWhileSpeaking() {
        begin()
        var action = scheduler.tick(at: 1050, loudness: 0.9)
        #expect(action == .none)
        action = scheduler.tick(at: 1054.9, loudness: 0.9)
        #expect(action == .none)
    }

    @Test mutating func rotatesAt55SecondsWhateverTheLevel() {
        begin()
        var action = scheduler.tick(at: 1054.9, loudness: 0.9)
        #expect(action == .none)
        action = scheduler.tick(at: 1055, loudness: 0.9)
        #expect(action == .rotate)
    }

    @Test mutating func ageStartsOverAfterARotation() {
        begin()
        var action = scheduler.tick(at: 1055, loudness: 0.9)
        #expect(action == .rotate)
        action = scheduler.tick(at: 1056, loudness: 0)
        #expect(action == .none)
        action = scheduler.tick(at: 1109.9, loudness: 0.9)
        #expect(action == .none)
        action = scheduler.tick(at: 1110, loudness: 0.9)
        #expect(action == .rotate)
    }

    @Test mutating func ageStartsOverWhenToldAboutAnotherRotation() {
        begin()
        scheduler.segmentStarted(at: 1050)
        let action = scheduler.tick(at: 1055, loudness: 0.9)
        #expect(action == .none)
    }

    @Test mutating func aSegmentEndedByItselfIsReplacedAtOnce() {
        begin()
        let action = scheduler.segmentEnded(at: 1020, heardText: true)
        #expect(action == .rotate)
    }

    @Test mutating func givesUpAfterFiveQuickFailuresWithoutText() {
        begin()
        var time = 1000.0
        var action = SegmentScheduler.Action.none
        for _ in 0..<4 {
            time += 0.5
            action = scheduler.segmentEnded(at: time, heardText: false)
            #expect(action == .rotate)
        }
        time += 0.5
        action = scheduler.segmentEnded(at: time, heardText: false)
        #expect(action == .giveUp)
    }

    @Test mutating func hearingTextResetsTheFailureCount() {
        begin()
        var time = 1000.0
        var action = SegmentScheduler.Action.none
        for _ in 0..<4 {
            time += 0.5
            action = scheduler.segmentEnded(at: time, heardText: false)
            #expect(action == .rotate)
        }
        time += 0.5
        action = scheduler.segmentEnded(at: time, heardText: true)
        #expect(action == .rotate)
        for _ in 0..<4 {
            time += 0.5
            action = scheduler.segmentEnded(at: time, heardText: false)
            #expect(action == .rotate)
        }
    }

    @Test mutating func aSlowFailureAfterHearingSoundCounts() {
        begin()
        var time = 1000.0
        var action = SegmentScheduler.Action.none
        for _ in 0..<5 {
            action = scheduler.tick(at: time + 1, loudness: 0.8)
            time += 20
            action = scheduler.segmentEnded(at: time, heardText: false)
        }
        #expect(action == .giveUp)
    }

    @Test mutating func soundHeardInAnEarlierSegmentDoesNotCountForALaterOne() {
        begin()
        _ = scheduler.tick(at: 1001, loudness: 0.8)
        _ = scheduler.segmentEnded(at: 1020, heardText: true)
        var time = 1020.0
        for _ in 0..<10 {
            time += 20
            let action = scheduler.segmentEnded(at: time, heardText: false)
            #expect(action == .rotate)
        }
    }

    @Test mutating func aLongSilenceEndingIsNotAFailure() {
        begin()
        var time = 1000.0
        for _ in 0..<10 {
            time += 20
            let action = scheduler.segmentEnded(at: time, heardText: false)
            #expect(action == .rotate)
        }
    }

    @Test mutating func stopsAfterThirtyMinutesOnlyOnce() {
        begin()
        var action = scheduler.tick(at: 1000 + 1799.9, loudness: 0.9)
        #expect(action == .rotate)
        action = scheduler.tick(at: 1000 + 1800, loudness: 0.9)
        #expect(action == .autoStop)
        action = scheduler.tick(at: 1000 + 1800.1, loudness: 0.9)
        #expect(action == .none)
    }

    @Test func loudnessIsScaledFromDecibels() {
        #expect(SegmentScheduler.loudness(rms: 0) == 0)
        #expect(SegmentScheduler.loudness(rms: 0.001) == 0)
        #expect(SegmentScheduler.loudness(rms: 1) == 1)
        let middle = SegmentScheduler.loudness(rms: 0.0316)
        #expect(abs(middle - 0.5) < 0.01)
    }
}
