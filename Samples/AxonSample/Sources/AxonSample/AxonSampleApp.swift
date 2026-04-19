import SwiftUI

@main
struct AxonSampleApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup("AxonSample") {
            ContentView()
                .environmentObject(store)
        }
    }
}
