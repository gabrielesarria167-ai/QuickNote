import AppKit
import SwiftData

/// Starts and stops voice recordings and decides where the transcript goes: appended to the note in
/// the capture panel or the main window, or saved as a new note.
@MainActor
@Observable
final class VoiceCaptureController {
    /// Chosen once, when the recording starts.
    private enum Target {
        /// The capture panel, identified by the session it was opened in.
        case panel(session: Int)
        case openNote(Note)
        case newNote
    }

    private let container: ModelContainer
    private let capture: CapturePanelController
    private let openNote: OpenNoteTracker

    @ObservationIgnored private let recorder = VoiceRecorder()
    @ObservationIgnored private lazy var pill = RecordingPill(
        recorder: recorder,
        onStop: { [weak self] in self?.finish() },
        onCancel: { [weak self] in self?.cancel() }
    )
    @ObservationIgnored private var target = Target.newNote
    /// Set as soon as a stop is requested; the recorder only changes state a moment later.
    @ObservationIgnored private var isStopping = false

    /// The note most recently created from a recording, so the main window can select it.
    private(set) var lastCreatedNote: Note?

    /// True from the first ⌃⌥R until the transcript is saved.
    var isRecording: Bool { recorder.state != .idle }

    init(container: ModelContainer, capture: CapturePanelController, openNote: OpenNoteTracker) {
        self.container = container
        self.capture = capture
        self.openNote = openNote
        recorder.onAutoStop = { [weak self] in self?.finish() }
    }

    func toggle() {
        switch recorder.state {
        case .idle:
            start()
        case .starting:
            // Still waiting for a permission prompt: abandon it.
            cancel()
        case .recording:
            finish()
        case .finishing:
            break
        }
    }

    /// Starts a recording. `preferNote` (the note selected in the main window) wins over wherever the
    /// transcript would otherwise go.
    func start(preferNote: Note? = nil) {
        guard recorder.state == .idle else { return }
        target = chooseTarget(preferNote: preferNote)
        isStopping = false
        Task {
            do {
                try await recorder.start()
                pill.showRecording()
            } catch is CancellationError {
                // Cancelled while waiting for permission; nothing to show.
            } catch {
                pill.showError(error.localizedDescription)
            }
        }
    }

    private func chooseTarget(preferNote: Note?) -> Target {
        if let preferNote { return .openNote(preferNote) }
        let keyEditorNote = openNote.window?.isKeyWindow == true ? openNote.note : nil
        switch RecordTargetKind.choose(panelOpen: capture.isOpen, hasKeyEditorNote: keyEditorNote != nil) {
        case .panel:
            return .panel(session: capture.session)
        case .openNote:
            return keyEditorNote.map { .openNote($0) } ?? .newNote
        case .newNote:
            return .newNote
        }
    }

    /// Stops listening and saves what was said.
    private func finish() {
        guard recorder.state == .recording, !isStopping else { return }
        isStopping = true
        Task {
            let text = await recorder.stop()
            pill.dismiss()
            isStopping = false
            save(text)
        }
    }

    private func cancel() {
        recorder.cancel()
        pill.dismiss()
    }

    private func save(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch target {
        case .panel(let session):
            // The panel saves itself when it closes. If it was closed (clicking away, or a permission
            // prompt taking focus) or reopened since, the transcript becomes its own note.
            if capture.isOpen, capture.session == session {
                capture.appendTranscript(text)
                return
            }
        case .openNote(let note):
            if note.modelContext != nil, !note.isDeleted {
                note.text = TranscriptAccumulator.appending(text, to: note.text)
                note.updatedAt = .now
                try? container.mainContext.save()
                return
            }
        case .newNote:
            break
        }

        let note = Note(text: text)
        container.mainContext.insert(note)
        try? container.mainContext.save()
        lastCreatedNote = note
    }
}
