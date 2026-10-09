import AppKit
import SwiftData

/// Starts and stops voice recordings and decides where the transcript goes: appended to the note in
/// the capture panel or the main window, or saved as a new note.
@MainActor
@Observable
final class VoiceCaptureController {
    private let container: ModelContainer
    private let capture: CapturePanelController
    private let openNote: OpenNoteTracker

    @ObservationIgnored private let recorder = VoiceRecorder()
    @ObservationIgnored private lazy var pill = RecordingPill(
        recorder: recorder,
        onStop: { [weak self] in self?.finish() },
        onCancel: { [weak self] in self?.cancel() }
    )
    /// Chosen once, when the recording starts.
    @ObservationIgnored private var target = RecordTarget<Note>.newNote
    /// Set as soon as a stop is requested; the recorder only changes state a moment later.
    @ObservationIgnored private var isStopping = false
    /// Counts starts and cancels, so a start that was cancelled before it began can tell.
    @ObservationIgnored private var startID = 0
    /// Set as soon as a start is requested; the recorder only changes state a moment later.
    private var isStarting = false

    /// The note most recently created from a recording, so the main window can select it.
    private(set) var lastCreatedNote: Note?

    /// True from the first ⌃⌥R until the transcript is saved.
    var isRecording: Bool { isStarting || recorder.state != .idle }

    init(container: ModelContainer, capture: CapturePanelController, openNote: OpenNoteTracker) {
        self.container = container
        self.capture = capture
        self.openNote = openNote
        recorder.onStopRequested = { [weak self] error in self?.finish(error: error) }
    }

    func toggle() {
        if isStarting || recorder.state == .starting {
            // Still waiting for a permission prompt: abandon it.
            cancel()
        } else if recorder.state == .idle {
            start()
        } else {
            finish()
        }
    }

    /// Starts a recording. `preferNote` (the note selected in the main window) wins over wherever the
    /// transcript would otherwise go.
    func start(preferNote: Note? = nil) {
        guard !isRecording else { return }
        target = chooseTarget(preferNote: preferNote)
        isStopping = false
        isStarting = true
        startID += 1
        let id = startID
        // Shown right away: a permission prompt can keep the first start waiting a while.
        pill.showRecording(below: capture.frame)
        Task {
            guard id == startID else { return }
            do {
                try await recorder.start()
            } catch is CancellationError {
                // Cancelled while waiting for permission; nothing to show.
            } catch let error as VoiceRecorderError {
                pill.showError(error)
            } catch {
                pill.dismiss()
            }
            if id == startID { isStarting = false }
        }
    }

    private func chooseTarget(preferNote: Note?) -> RecordTarget<Note> {
        let keyEditorNote = openNote.window?.isKeyWindow == true ? openNote.note : nil
        let panel = capture.isOpen ? (session: capture.session, note: capture.shownNote) : nil
        return RecordTarget.choose(preferred: preferNote, panel: panel, keyEditorNote: keyEditorNote)
    }

    /// Stops listening and saves what was said. If the recording had to stop because of `error`, the
    /// pill then says why.
    private func finish(error: VoiceRecorderError? = nil) {
        guard recorder.state == .recording, !isStopping else { return }
        isStopping = true
        Task {
            let text = await recorder.stop()
            pill.dismiss()
            isStopping = false
            save(text)
            if let error {
                let nothingHeard = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                pill.showError(error == .recognitionStopped && nothingHeard ? .recognitionNotWorking : error)
            }
        }
    }

    private func cancel() {
        startID += 1
        isStarting = false
        recorder.cancel()
        pill.dismiss()
    }

    private func save(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch target {
        case .panel(let session, let note):
            // The panel saves itself when it closes. If it was closed (clicking away, or a permission
            // prompt taking focus) or reopened since, the text still goes to the note it showed,
            // or becomes a new note if it showed the new one.
            if capture.isOpen, capture.session == session {
                capture.appendTranscript(text, to: note)
                return
            }
            if let note, append(text, to: note) { return }
        case .openNote(let note):
            if append(text, to: note) { return }
        case .newNote:
            break
        }

        let note = Note(text: text)
        container.mainContext.insert(note)
        try? container.mainContext.save()
        lastCreatedNote = note
    }

    /// Adds the text to an existing note. Returns false if the note is gone.
    private func append(_ text: String, to note: Note) -> Bool {
        guard note.modelContext != nil, !note.isDeleted else { return false }
        if capture.isShowing(note) {
            // The editor in the panel has this note's text; the panel writes it back when it closes.
            capture.appendTranscript(text, to: note)
        } else {
            note.text = note.text.appendingParagraph(text)
            note.updatedAt = .now
            try? container.mainContext.save()
        }
        return true
    }
}
