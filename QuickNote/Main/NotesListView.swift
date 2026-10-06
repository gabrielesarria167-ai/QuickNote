import SwiftData
import SwiftUI

struct NotesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AccessibilityPermission.self) private var permission
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
            }
        } detail: {
            Group {
                if let selectedNote {
                    NoteEditorView(note: selectedNote)
                } else {
                    ContentUnavailableView(
                        "No Note Selected",
                        systemImage: "lightbulb",
                        description: Text("Tap ⌃ and ⌥ together from any app to capture an idea.")
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

    /// Notes created with ⌘N and left empty are removed when you move away.
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
