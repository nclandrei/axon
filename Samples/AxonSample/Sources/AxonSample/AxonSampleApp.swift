import SwiftUI

@main
struct AxonSampleApp: App {
    var body: some Scene {
        WindowGroup("AxonSample") {
            Text("AxonSample")
                .frame(minWidth: 640, minHeight: 400)
                .accessibilityIdentifier("mainPlaceholder")
        }
    }
}
