import Foundation

/// Where a voice recording ends up. `NoteRef` stands for a note (the `Note` model in the app).
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum RecordTarget<NoteRef: Equatable>: Equatable {
    /// Added to what the capture panel shows: an older note, or the new note if `note` is nil.
    /// `session` identifies the opening of the panel.
    case panel(session: Int, note: NoteRef?)
    /// Added to a note in the main window.
    case openNote(NoteRef)
    /// Saved as a new note.
    case newNote

    /// A note asked for explicitly wins, then the capture panel, then the note the main window is
    /// showing (only when it is in front), otherwise a new note.
    static func choose(
        preferred: NoteRef?,
        panel: (session: Int, note: NoteRef?)?,
        keyEditorNote: NoteRef?
    ) -> RecordTarget {
        if let preferred { return .openNote(preferred) }
        if let panel { return .panel(session: panel.session, note: panel.note) }
        if let keyEditorNote { return .openNote(keyEditorNote) }
        return .newNote
    }
}
