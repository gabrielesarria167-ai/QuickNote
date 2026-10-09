import Foundation

/// Where a voice recording ends up.
enum RecordTargetKind: Equatable {
    /// Appended to the note shown in the capture panel.
    case panel
    /// Appended to the note open in the main window.
    case openNote
    /// Saved as a new note.
    case newNote

    /// The panel wins, then the note open in the main window, otherwise a new note.
    ///
    /// Pure logic with no AppKit dependency so it can be unit tested.
    static func choose(panelOpen: Bool, hasKeyEditorNote: Bool) -> RecordTargetKind {
        if panelOpen { return .panel }
        if hasKeyEditorNote { return .openNote }
        return .newNote
    }
}
