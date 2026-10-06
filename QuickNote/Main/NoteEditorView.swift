import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note

    var body: some View {
        TextEditor(text: $note.text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(note.title)
            .navigationSubtitle(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            .onChange(of: note.text) {
                note.updatedAt = .now
            }
    }
}
