import SwiftData
import SwiftUI

/// The whole iPhone app: a note with the keyboard up, and the past notes one tap away.
/// There's no save button — the note saves when the app goes to the background, when a new note
/// starts or when the list opens, like `esc saves` on the Mac. A blank note is never saved.
struct CaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var text = ""
    /// The saved note being edited, or nil while the text is a new note that hasn't been saved yet.
    @State private var editing: Note?
    @State private var showingList = false
    @State private var saveError: String?
    @FocusState private var focused: Bool
    private let requests = NewNoteRequests.shared

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .font(.system(size: 17))
                    .focused($focused)
                    .accessibilityLabel("Note text")
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("What's the idea?")
                                .font(.system(size: 17))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .toolbar {
                if editing != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("New Note", systemImage: "square.and.pencil", action: newNote)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Notes", systemImage: "list.bullet") {
                        save()
                        showingList = true
                    }
                }
            }
            .sheet(isPresented: $showingList) {
                NoteList(notes: notes, open: open, delete: delete)
            }
            .alert("QuickNote couldn't save this note", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        .onAppear { focused = true }
        .onChange(of: requests.count) { newNote() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { save() }
            if phase == .active && !showingList { focused = true }
        }
    }

    private var caption: String {
        guard let editing else { return "New note" }
        return "Note from " + editing.createdAt.formatted(.relative(presentation: .named))
    }

    /// Saves what's showing and starts a blank note — what the Action Button / Back Tap does.
    private func newNote() {
        save()
        editing = nil
        text = ""
        showingList = false
        focused = true
    }

    private func open(_ note: Note) {
        save()
        editing = note
        text = note.text
        showingList = false
        focused = true
    }

    private func delete(_ note: Note) {
        if note === editing {
            editing = nil
            text = ""
        }
        context.delete(note)
        commit()
    }

    private func save() {
        if let editing {
            guard editing.text != text else { return }
            editing.text = text
            editing.updatedAt = .now
            if editing.isBlank {
                context.delete(editing)
                self.editing = nil
            }
        } else {
            let note = Note(text: text)
            guard !note.isBlank else { return }
            context.insert(note)
            editing = note
        }
        commit()
    }

    /// Writes to disk now: going to the background is the last chance before iOS may quit the app.
    private func commit() {
        do {
            try context.save()
        } catch {
            saveError = "\(error.localizedDescription)\n\nThe text is still on screen — copy it somewhere safe."
        }
    }
}

private struct NoteList: View {
    let notes: [Note]
    let open: (Note) -> Void
    let delete: (Note) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { note in
                    Button { open(note) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .lineLimit(1)
                            if !note.preview.isEmpty {
                                Text(note.preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    offsets.map { notes[$0] }.forEach(delete)
                }
            }
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "lightbulb")
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
