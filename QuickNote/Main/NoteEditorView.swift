import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note

    var body: some View {
        FormattedTextEditor(text: $note.text, fontSize: 14)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(note.title)
            .navigationSubtitle(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            .onChange(of: note.text) {
                note.updatedAt = .now
            }
    }
}
