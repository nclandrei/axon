import SwiftUI

struct Editor: View {
    @ObservedObject var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: Binding(
                get: { note.title },
                set: { new in note.title = new; note.isDirty = true }
            ))
            .font(.title2)
            .textFieldStyle(.plain)
            .accessibilityIdentifier("noteTitleField")

            Divider()

            TextEditor(text: Binding(
                get: { note.body },
                set: { new in note.body = new; note.isDirty = true }
            ))
            .font(.body)
            .accessibilityIdentifier("noteBodyField")
        }
        .padding(16)
    }
}
