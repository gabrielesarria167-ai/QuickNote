import AppKit
import SwiftUI

/// Remembers which note the main window is showing, and that window, so a voice recording knows
/// whether it should add to a note. Only counts when the window is the key window (QuickNote is in
/// front); recording from another app makes a new note instead.
@MainActor
@Observable
final class OpenNoteTracker {
    weak var note: Note?
    weak var window: NSWindow?
}

/// Reports the window a view ended up in.
struct WindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowReportingView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}
