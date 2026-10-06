import Testing
@testable import QuickNote

struct ModifierChordDetectorTests {
    private var detector = ModifierChordDetector()

    private mutating func hold(_ keys: ModifierKeys, at time: Double) -> Bool {
        detector.modifiersChanged(to: keys, at: time)
    }

    @Test mutating func tappingControlOptionFires() {
        #expect(!hold([.control], at: 1.00))
        #expect(!hold([.control, .option], at: 1.05))
        #expect(!hold([.option], at: 1.20))
        #expect(hold([], at: 1.25))
    }

    @Test mutating func optionFirstAlsoFires() {
        #expect(!hold([.option], at: 1.00))
        #expect(!hold([.control, .option], at: 1.05))
        #expect(hold([], at: 1.20))
    }

    @Test mutating func shortcutWithAKeyDoesNotFire() {
        #expect(!hold([.control, .option], at: 1.0))
        detector.keyPressed()
        #expect(!hold([], at: 1.2))
    }

    @Test mutating func extraModifierDoesNotFire() {
        #expect(!hold([.control, .option], at: 1.0))
        #expect(!hold([.control, .option, .command], at: 1.1))
        #expect(!hold([.control, .option], at: 1.2))
        #expect(!hold([], at: 1.3))
    }

    @Test mutating func singleModifierDoesNotFire() {
        #expect(!hold([.control], at: 1.0))
        #expect(!hold([], at: 1.1))
        #expect(!hold([.option], at: 2.0))
        #expect(!hold([], at: 2.1))
    }

    @Test mutating func longHoldDoesNotFire() {
        #expect(!hold([.control, .option], at: 1.0))
        #expect(!hold([], at: 2.0))
    }

    @Test mutating func keyPressedWithNothingHeldIsIgnored() {
        detector.keyPressed()
        #expect(!hold([.control, .option], at: 1.0))
        #expect(hold([], at: 1.1))
    }

    @Test mutating func worksAgainAfterACancelledAttempt() {
        #expect(!hold([.control, .option], at: 1.0))
        detector.keyPressed()
        #expect(!hold([], at: 1.1))
        #expect(!hold([.control, .option], at: 2.0))
        #expect(hold([], at: 2.1))
    }
}
