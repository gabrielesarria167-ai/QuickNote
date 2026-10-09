import AppKit
import SwiftData
import SwiftUI

/// Shows the capture panel, lets you flip back through older notes by pressing
/// `.` and `-` together, and saves everything when it closes.
@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let container: ModelContainer
    private let draft = CaptureDraft()
    private let panelSize = NSSize(width: 620, height: 320)

    /// Text of the new note, kept aside while browsing older notes.
    private var newNoteText = ""
    /// Existing notes, newest first, loaded each time the panel opens.
    private var olderNotes: [Note] = []
    /// 0 is the new note; `n` is `olderNotes[n - 1]`.
    private var position = 0

    /// Whether the panel is showing.
    var isOpen: Bool { panel.isVisible }
    /// Changes every time the panel opens, so a caller can tell whether it's still the same opening.
    var session: Int { draft.session }

    private lazy var panel: CapturePanel = {
        let panel = CapturePanel(contentRect: NSRect(origin: .zero, size: panelSize))
        panel.contentView = NSHostingView(rootView: CaptureView(draft: draft))
        panel.delegate = self
        panel.onSubmit = { [weak self] in self?.commit() }
        panel.onFlip = { [weak self] in self?.showNextOlderNote() }
        return panel
    }()

    init(container: ModelContainer) {
        self.container = container
    }

    func toggle() {
        if panel.isVisible {
            commit()
        } else {
            show()
        }
    }

    func show() {
        let newestFirst = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        olderNotes = (try? container.mainContext.fetch(newestFirst)) ?? []
        newNoteText = ""
        position = 0
        draft.begin()
        updateCaption()
        panel.setFrameOrigin(originOnActiveScreen())
        panel.makeKeyAndOrderFront(nil)
    }

    /// The note the panel is showing, or nil for the new note (or when it's closed).
    var shownNote: Note? {
        position > 0 && position <= olderNotes.count ? olderNotes[position - 1] : nil
    }

    /// Where the panel is on screen, or nil when it's closed.
    var frame: NSRect? { panel.isVisible ? panel.frame : nil }

    /// Whether the panel is open on this note.
    func isShowing(_ note: Note) -> Bool {
        isOpen && shownNote === note
    }

    /// Adds a voice transcript as a new paragraph to the note the panel showed when the recording
    /// began (an older note, or the new note if `note` is nil), wherever it is now. What's on screen
    /// goes through `draft.text`, which `stashEditorText()` copies back to the note when you move on
    /// or close. A note that's out of sight is changed directly: `stashEditorText()` only ever writes
    /// the one being shown, so it can't overwrite this.
    func appendTranscript(_ text: String, to note: Note?) {
        if shownNote === note {
            draft.text = draft.text.appendingParagraph(text)
        } else if let note {
            note.text = note.text.appendingParagraph(text)
            note.updatedAt = .now
            try? container.mainContext.save()
        } else {
            newNoteText = newNoteText.appendingParagraph(text)
        }
    }

    /// Steps back to the next older note, wrapping around to the new note
    /// after the oldest one.
    func showNextOlderNote() {
        guard !olderNotes.isEmpty else { return }
        stashEditorText()
        position = (position + 1) % (olderNotes.count + 1)
        draft.text = position == 0 ? newNoteText : olderNotes[position - 1].text
        updateCaption()
    }

    /// Saves the new note (unless blank) and any edits to older notes, then
    /// hides the panel. Safe to call twice: hiding the panel resigns key,
    /// which calls back into this.
    func commit() {
        stashEditorText()
        let context = container.mainContext
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            context.insert(Note(text: text))
        }
        for note in olderNotes where note.isBlank {
            context.delete(note)
        }
        try? context.save()

        newNoteText = ""
        olderNotes = []
        position = 0
        draft.text = ""
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Writes what's in the editor back to the note currently shown.
    private func stashEditorText() {
        guard position > 0 else {
            newNoteText = draft.text
            return
        }
        let note = olderNotes[position - 1]
        if note.text != draft.text {
            note.text = draft.text
            note.updatedAt = .now
        }
    }

    private func updateCaption() {
        draft.canBrowse = !olderNotes.isEmpty
        guard position > 0 else {
            draft.caption = "New note"
            return
        }
        let note = olderNotes[position - 1]
        let number = olderNotes.count - position + 1
        let age = note.createdAt.formatted(.relative(presentation: .named))
        draft.caption = "Note \(number) of \(olderNotes.count) · \(age)"
    }

    // Clicking anywhere outside the panel saves and closes it.
    func windowDidResignKey(_ notification: Notification) {
        commit()
    }

    /// Horizontally centred, in the upper part of the screen under the mouse.
    private func originOnActiveScreen() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        return NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.minY + frame.height * 0.66 - panelSize.height / 2
        )
    }
}
