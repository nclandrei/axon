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
                    .keyboardShortcut("n", modifiers: .command)
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
            VStack(spacing: 0) {
                if let note = store.selectedNote {
                    Editor(note: note)
                    HStack {
                        Text(note.isDirty ? "modified" : "clean")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("dirtyStatus")
                            .accessibilityLabel("Save state")
                            .accessibilityValue(note.isDirty ? "modified" : "clean")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                } else {
                    Text("No note selected")
                        .accessibilityIdentifier("noSelectionPlaceholder")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .alert("Unsaved changes", isPresented: $store.showUnsavedSheet) {
            Button("Cancel", role: .cancel) { store.dismissSheetCancel() }
                .accessibilityIdentifier("sheetCancel")
            Button("Don't Save", role: .destructive) { store.dismissSheetDontSave() }
                .accessibilityIdentifier("sheetDontSave")
            Button("Save") { store.dismissSheetSave() }
                .accessibilityIdentifier("sheetSave")
        } message: {
            Text("Do you want to save before closing?")
        }
    }
}
