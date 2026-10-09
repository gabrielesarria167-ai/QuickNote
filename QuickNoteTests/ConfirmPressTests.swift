import Testing
@testable import QuickNote

struct ConfirmPressTests {
    @Test func theFirstPressOnlyArms() {
        var press = ConfirmPress()
        let confirmed = press.press(at: 10)
        #expect(!confirmed)
    }

    @Test func aSecondPressWithinTheWindowConfirms() {
        var press = ConfirmPress()
        _ = press.press(at: 10)
        let confirmed = press.press(at: 12.9)
        #expect(confirmed)
    }

    @Test func aSecondPressAfterTheWindowArmsAgain() {
        var press = ConfirmPress()
        _ = press.press(at: 10)
        let late = press.press(at: 13.5)
        let second = press.press(at: 14)
        #expect(!late)
        #expect(second)
    }

    @Test func confirmingResetsSoTheNextPressArmsAgain() {
        var press = ConfirmPress()
        _ = press.press(at: 10)
        let confirmed = press.press(at: 11)
        let next = press.press(at: 12)
        #expect(confirmed)
        #expect(!next)
    }

    @Test func resettingForgetsTheFirstPress() {
        var press = ConfirmPress()
        _ = press.press(at: 10)
        press.reset()
        let confirmed = press.press(at: 11)
        #expect(!confirmed)
    }
}
