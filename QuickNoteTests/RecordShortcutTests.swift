import Testing
@testable import QuickNote

struct RecordShortcutTests {
    private var detector = ModifierChordDetector()

    private mutating func hold(_ keys: ModifierKeys, at time: Double) -> Bool {
        detector.modifiersChanged(to: keys, at: time)
    }

    private func matches(_ held: ModifierKeys, _ key: String?, isRepeat: Bool = false) -> Bool {
        RecordShortcut.matches(held: held, key: key, isRepeat: isRepeat)
    }

    @Test func repeatsAreStillTheShortcutSoTheyCanBeKeptOutOfTextViews() {
        #expect(RecordShortcut.isShortcut(held: [.control, .option], key: "r"))
        #expect(!RecordShortcut.isShortcut(held: [.control, .option, .shift], key: "r"))
        #expect(!RecordShortcut.isShortcut(held: [.control, .option], key: "t"))
    }

    @Test func controlOptionRMatches() {
        #expect(matches([.control, .option], "r"))
    }

    @Test func uppercaseRMatches() {
        #expect(matches([.control, .option], "R"))
    }

    @Test func extraModifierDoesNotMatch() {
        #expect(!matches([.control, .option, .shift], "r"))
        #expect(!matches([.control, .option, .command], "r"))
    }

    @Test func otherModifiersDoNotMatch() {
        #expect(!matches([.command], "r"))
        #expect(!matches([.control], "r"))
        #expect(!matches([.option], "r"))
        #expect(!matches([.control, .shift], "r"))
    }

    @Test func plainRDoesNotMatch() {
        #expect(!matches([], "r"))
        #expect(!matches([.shift], "R"))
    }

    @Test func keyRepeatDoesNotMatch() {
        #expect(!matches([.control, .option], "r", isRepeat: true))
    }

    @Test func otherKeysDoNotMatch() {
        #expect(!matches([.control, .option], "t"))
        #expect(!matches([.control, .option], "rr"))
        #expect(!matches([.control, .option], ""))
    }

    @Test func missingKeyDoesNotMatch() {
        #expect(!matches([.control, .option], nil))
    }

    @Test mutating func pressingRDoesNotFireTheControlOptionTap() {
        // ⌃⌥R must never also open the capture panel.
        #expect(!hold([.control, .option], at: 1.0))
        detector.keyPressed()
        #expect(!hold([], at: 1.1))
    }
}
