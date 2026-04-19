import SwiftUI

struct NoteRow: View {
    @ObservedObject var note: Note

    var body: some View {
        Text(note.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("noteRow-\(note.id.uuidString)")
            .accessibilityLabel(note.title)
    }
}
