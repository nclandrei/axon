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
                Button("New Note") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
