import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { store.createNote() }) {
                        Label("New Note", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newNoteButton")
                    .accessibilityLabel("New Note")
                    Spacer()
                }
                .padding(8)

                List(selection: $store.selectedID) {
                    ForEach(store.notes) { note in
                        NoteRow(note: note).tag(note.id as UUID?)
                    }
                }
                .accessibilityIdentifier("notesList")
            }
        } detail: {
            if let note = store.selectedNote {
                Editor(note: note)
            } else {
                Text("No note selected")
                    .accessibilityIdentifier("noSelectionPlaceholder")
            }
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}
