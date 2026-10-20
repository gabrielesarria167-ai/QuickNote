import AppKit
import SwiftData
import SwiftUI

/// Shows the capture panel, lets you flip back through older notes by pressing
/// `.` and `-` together (and forward again with `<` and `z`), and saves everything when it closes.
@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let container: ModelContainer
    private let draft = CaptureDraft()
    private let panelSize = NSSize(width: 620, height: 320)

    /// Text of the new note, kept aside while browsing older notes.
    private var newNoteText = ""
    /// Files attached to the new note, kept aside the same way.
    private var newNoteAttachments: [String] = []
    /// While the file picker is up the panel isn't key, which must not save and close it.
    private var isPickingFiles = false
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
        panel.contentView = NSHostingView(rootView: CaptureView(draft: draft) { [weak self] in self?.pickFiles() })
        panel.delegate = self
        panel.onSubmit = { [weak self] in self?.commit() }
        panel.onFlip = { [weak self] in self?.flip(by: $0) }
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
        newNoteAttachments = []
        position = 0
        draft.begin()
        updateCaption()
        panel.setFrameOrigin(originOnActiveScreen())
        focusPanel()
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

    /// Steps to an older note (`step` 1) or a newer one (-1). Past the oldest note it wraps around to
    /// the new note, and back from the new note to the oldest.
    func flip(by step: Int) {
        guard !olderNotes.isEmpty else { return }
        stashEditorText()
        let count = olderNotes.count + 1
        position = (position + step + count) % count
        draft.text = position == 0 ? newNoteText : olderNotes[position - 1].text
        draft.attachments = position == 0 ? newNoteAttachments : olderNotes[position - 1].attachments
        updateCaption()
    }

    /// Saves the new note (unless blank) and any edits to older notes, then
    /// hides the panel. Safe to call twice: hiding the panel resigns key,
    /// which calls back into this.
    func commit() {
        // Toggling the hotkey while choosing files closes the picker without attaching anything.
        if isPickingFiles {
            isPickingFiles = false
            if let sheet = panel.attachedSheet {
                panel.endSheet(sheet)
            }
        }
        stashEditorText()
        let context = container.mainContext
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty || !newNoteAttachments.isEmpty {
            context.insert(Note(text: text, attachments: newNoteAttachments))
        }
        for note in olderNotes where note.isBlank {
            context.delete(note)
        }
        try? context.save()

        newNoteText = ""
        newNoteAttachments = []
        olderNotes = []
        position = 0
        draft.text = ""
        draft.attachments = []
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Opens the file picker as a sheet on the panel and attaches what's chosen to the note showing. A sheet
    /// shows wherever the panel is; app-modal it could open on another Space (e.g. under a full-screen app)
    /// and block the panel unseen, which looked frozen.
    func pickFiles() {
        guard !isPickingFiles else { return }
        isPickingFiles = true
        Attachments.pickFiles(sheetFor: panel) { [weak self] urls in
            guard let self, isPickingFiles else { return }
            isPickingFiles = false
            draft.attachments += Attachments.add(urls)
            focusPanel()
        }
    }

    /// Over a full-screen app `makeKeyAndOrderFront` shows the panel without making it key, so typing and
    /// Esc went to the app underneath.
    private func focusPanel() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// Writes what's in the editor back to the note currently shown.
    private func stashEditorText() {
        guard position > 0 else {
            newNoteText = draft.text
            newNoteAttachments = draft.attachments
            return
        }
        let note = olderNotes[position - 1]
        if note.text != draft.text || note.attachments != draft.attachments {
            note.text = draft.text
            note.attachments = draft.attachments
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
        guard !isPickingFiles else { return }
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
