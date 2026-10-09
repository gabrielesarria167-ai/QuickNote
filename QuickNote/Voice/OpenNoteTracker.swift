import AppKit

/// Remembers which note the main window is showing, and that window, so a voice recording knows
/// whether it should add to a note. Only counts when the window is the key window (QuickNote is in
/// front); recording from another app makes a new note instead.
@MainActor
@Observable
final class OpenNoteTracker {
    weak var note: Note?
    weak var window: NSWindow?
}
