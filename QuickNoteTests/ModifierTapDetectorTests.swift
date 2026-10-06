import Testing
@testable import QuickNote

struct ModifierTapDetectorTests {
    private var detector = ModifierTapDetector()
    private let rightShift: UInt16 = 60
    private let leftShift: UInt16 = 56

    private mutating func press(_ keyCode: UInt16, at time: Double) -> Bool {
        detector.modifierChanged(keyCode: keyCode, isDown: true, timestamp: time)
    }

    private mutating func release(_ keyCode: UInt16, at time: Double) -> Bool {
        detector.modifierChanged(keyCode: keyCode, isDown: false, timestamp: time)
    }

    @Test mutating func quickTapFires() {
        #expect(!press(rightShift, at: 1.0))
        #expect(release(rightShift, at: 1.1))
    }

    @Test mutating func typingACapitalDoesNotFire() {
        #expect(!press(rightShift, at: 1.0))
        detector.keyPressed()
        #expect(!release(rightShift, at: 1.1))
    }

    @Test mutating func longHoldDoesNotFire() {
        #expect(!press(rightShift, at: 1.0))
        #expect(!release(rightShift, at: 1.6))
    }

    @Test mutating func leftShiftDoesNotFire() {
        #expect(!press(leftShift, at: 1.0))
        #expect(!release(leftShift, at: 1.1))
    }

    @Test mutating func otherModifierDuringHoldCancels() {
        #expect(!press(rightShift, at: 1.0))
        #expect(!press(55, at: 1.05))
        #expect(!release(rightShift, at: 1.1))
    }

    @Test mutating func releaseWithoutPressDoesNotFire() {
        #expect(!release(rightShift, at: 1.0))
    }
}
