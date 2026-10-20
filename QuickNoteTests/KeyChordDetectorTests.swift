import Testing
@testable import QuickNote

struct KeyChordDetectorTests {
    private var detector = KeyChordDetector()

    private mutating func down(_ key: String, at time: Double, isRepeat: Bool = false, modifier: Bool = false) -> KeyChordDetector.Decision {
        detector.keyDown(key, at: time, isRepeat: isRepeat, hasShortcutModifier: modifier)
    }

    private mutating func up(_ key: String) -> KeyChordDetector.Decision {
        detector.keyUp(key)
    }

    /// The timeout for the most recent hold.
    private mutating func timeOut() -> Bool {
        detector.timedOut(generation: detector.generation)
    }

    @Test mutating func bothTogetherIsTheChord() {
        #expect(down(".", at: 1.00) == .hold)
        #expect(down("-", at: 1.03) == .chord([".", "-"]))
        #expect(up(".") == .swallow)
        #expect(up("-") == .swallow)
    }

    @Test mutating func eitherOrderWorks() {
        #expect(down("-", at: 1.00) == .hold)
        #expect(down(".", at: 1.02) == .chord([".", "-"]))
    }

    @Test mutating func aLoneDotIsTypedAfterTheWindow() {
        #expect(down(".", at: 1.0) == .hold)
        #expect(timeOut())
        #expect(up(".") == .pass)
    }

    @Test mutating func aQuickTapIsTypedOnRelease() {
        #expect(down(".", at: 1.0) == .hold)
        #expect(up(".") == .flushThenPass)
        #expect(!timeOut())
    }

    @Test mutating func typingDotThenDashSlowlyTypesBoth() {
        #expect(down(".", at: 1.00) == .hold)
        #expect(down("-", at: 1.20) == .flushThenHold)
        #expect(timeOut())
    }

    @Test mutating func anotherKeyDeliversTheHeldOneFirst() {
        #expect(down(".", at: 1.00) == .hold)
        #expect(down(" ", at: 1.02) == .flushThenPass)
        #expect(down("a", at: 1.10) == .pass)
    }

    @Test mutating func repeatsWhileHoldingTheChordAreSwallowed() {
        #expect(down(".", at: 1.00) == .hold)
        #expect(down("-", at: 1.02) == .chord([".", "-"]))
        #expect(down(".", at: 1.50, isRepeat: true) == .swallow)
        #expect(down("-", at: 1.55, isRepeat: true) == .swallow)
    }

    @Test mutating func shortcutsAreNotTheChord() {
        #expect(down(".", at: 1.00, modifier: true) == .pass)
        #expect(down("-", at: 1.01, modifier: true) == .pass)
    }

    @Test mutating func sameKeyTwiceIsTwoCharacters() {
        #expect(down(".", at: 1.00) == .hold)
        #expect(down(".", at: 1.03) == .flushThenHold)
    }

    @Test mutating func worksAgainAfterAChord() {
        #expect(down(".", at: 1.00) == .hold)
        #expect(down("-", at: 1.02) == .chord([".", "-"]))
        #expect(up(".") == .swallow)
        #expect(up("-") == .swallow)
        #expect(down("-", at: 2.00) == .hold)
        #expect(down(".", at: 2.01) == .chord([".", "-"]))
    }

    @Test mutating func eachPairIsItsOwnChord() {
        detector.chords = [[".", "-"], ["<", "z"]]
        #expect(down("z", at: 1.00) == .hold)
        #expect(down("<", at: 1.02) == .chord(["<", "z"]))
        #expect(up("z") == .swallow)
        #expect(up("<") == .swallow)
        // Keys from different pairs are just typed.
        #expect(down(".", at: 2.00) == .hold)
        #expect(down("z", at: 2.01) == .flushThenHold)
        #expect(timeOut())
    }
}
