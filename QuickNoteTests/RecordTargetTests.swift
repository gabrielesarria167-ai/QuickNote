import Testing
@testable import QuickNote

struct RecordTargetTests {
    @Test func openPanelIsTheTarget() {
        #expect(RecordTargetKind.choose(panelOpen: true, hasKeyEditorNote: false) == .panel)
    }

    @Test func openNoteInTheMainWindowIsTheTarget() {
        #expect(RecordTargetKind.choose(panelOpen: false, hasKeyEditorNote: true) == .openNote)
    }

    @Test func otherwiseItIsANewNote() {
        #expect(RecordTargetKind.choose(panelOpen: false, hasKeyEditorNote: false) == .newNote)
    }

    @Test func panelWinsOverTheEditor() {
        #expect(RecordTargetKind.choose(panelOpen: true, hasKeyEditorNote: true) == .panel)
    }
}
