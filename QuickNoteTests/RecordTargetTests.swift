import Testing
@testable import QuickNote

struct RecordTargetTests {
    private func choose(
        preferred: Int? = nil,
        panel: (session: Int, note: Int?)? = nil,
        keyEditorNote: Int? = nil
    ) -> RecordTarget<Int> {
        RecordTarget.choose(preferred: preferred, panel: panel, keyEditorNote: keyEditorNote)
    }

    @Test func openPanelIsTheTarget() {
        #expect(choose(panel: (session: 4, note: nil)) == .panel(session: 4, note: nil))
    }

    @Test func panelRemembersTheNoteItShowed() {
        #expect(choose(panel: (session: 4, note: 9)) == .panel(session: 4, note: 9))
    }

    @Test func openNoteInTheMainWindowIsTheTarget() {
        #expect(choose(keyEditorNote: 7) == .openNote(7))
    }

    @Test func otherwiseItIsANewNote() {
        #expect(choose() == .newNote)
    }

    @Test func panelWinsOverTheEditor() {
        #expect(choose(panel: (session: 1, note: nil), keyEditorNote: 7) == .panel(session: 1, note: nil))
    }

    @Test func preferredNoteWinsOverEverything() {
        #expect(choose(preferred: 2, panel: (session: 1, note: nil), keyEditorNote: 7) == .openNote(2))
    }
}
