import SwiftUI

@main
struct AxonSampleApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup("AxonSample") {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(store.selectedNote == nil)
            }
            CommandGroup(after: .saveItem) {
                Button("Delete") { store.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.selectedNote == nil)
            }
            CommandGroup(replacing: .windowArrangement) {
                Button("Close") {
                    _ = store.attemptClose()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
