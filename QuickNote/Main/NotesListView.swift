import SwiftData
import SwiftUI

struct NotesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AccessibilityPermission.self) private var permission
    @Environment(VoiceCaptureController.self) private var voice
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var selection: PersistentIdentifier?
    @State private var search = ""

    private var filteredNotes: [Note] {
        guard !search.isEmpty else { return notes }
        return notes.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    private var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(filteredNotes) { note in
                    NoteRow(note: note)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(note) }
                        }
                }
            }
            .onDeleteCommand {
                if let selectedNote { delete(selectedNote) }
            }
            .searchable(text: $search, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                Button("New Note", systemImage: "square.and.pencil", action: newNote)
                    .keyboardShortcut("n")
                Button(action: recordVoiceNote) {
                    Image(systemName: voice.isTranscribing ? "waveform" : voice.isRecording ? "stop.fill" : "mic")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(voice.isRecording && !voice.isTranscribing ? Color.red : Color.primary)
                }
                .disabled(voice.isTranscribing)
                .accessibilityLabel(voice.isTranscribing ? "Transcribing" : voice.isRecording ? "Stop Recording" : "Record Voice Note")
                .help(voice.isTranscribing ? "Transcribing the voice note…" : "Record a voice note (⌃⌥R)")
            }
        } detail: {
            Group {
                if let selectedNote {
                    // A fresh editor per note, so switching notes isn't seen as an edit.
                    NoteEditorView(note: selectedNote)
                        .id(selectedNote.id)
                } else {
                    ContentUnavailableView(
                        "No Note Selected",
                        systemImage: "lightbulb",
                        description: Text("Tap ⌃ and ⌥ together from any app to capture an idea, or press ⌃⌥R to say it.")
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                if !permission.isGranted {
                    PermissionBanner(permission: permission)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onChange(of: selection) { oldValue, _ in
            discardIfBlank(oldValue)
        }
        .onChange(of: voice.lastCreatedNote) { _, note in
            guard let note else { return }
            search = ""
            selection = note.id
        }
        .onDisappear { discardIfBlank(selection) }
    }

    /// Stops a recording in progress; otherwise starts one that adds to the selected note, if any.
    private func recordVoiceNote() {
        if voice.isRecording {
            voice.toggle()
        } else {
            voice.start(preferNote: selectedNote)
        }
    }

    private func newNote() {
        let note = Note()
        context.insert(note)
        search = ""
        selection = note.id
    }

    private func delete(_ note: Note) {
        if note.id == selection {
            selection = nil
        }
        context.delete(note)
    }

    /// Notes created with ⌘N and left empty are removed when you move away or close the window.
    private func discardIfBlank(_ id: PersistentIdentifier?) {
        guard let note = notes.first(where: { $0.id == id }), note.isBlank else { return }
        context.delete(note)
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.updatedAt, format: .relative(presentation: .named))
                if !note.preview.isEmpty {
                    Text(note.preview).lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
