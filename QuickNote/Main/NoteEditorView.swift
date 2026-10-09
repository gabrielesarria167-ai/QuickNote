import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(OpenNoteTracker.self) private var openNote

    var body: some View {
        FormattedTextEditor(text: $note.text, fontSize: 14)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .safeAreaInset(edge: .bottom) {
                MarkdownCheatSheet()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(note.title)
            .navigationSubtitle(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            .onChange(of: note.text) {
                note.updatedAt = .now
            }
            .background(WindowReader { openNote.window = $0 })
            .onAppear { openNote.note = note }
            // The next note's editor may already have appeared, so only clear our own entry.
            .onDisappear {
                if openNote.note === note { openNote.note = nil }
            }
    }
}
