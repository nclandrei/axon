import SwiftUI

struct UnsavedSheet: View {
    let onSave: () -> Void
    let onDontSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You have unsaved changes.")
                .font(.headline)
            Text("Do you want to save before closing?")

            HStack {
                Button("Cancel") { onCancel() }
                    .accessibilityIdentifier("sheetCancel")
                Spacer()
                Button("Don't Save") { onDontSave() }
                    .accessibilityIdentifier("sheetDontSave")
                Button("Save") { onSave() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("sheetSave")
            }
        }
        .padding(24)
        .frame(minWidth: 340)
    }
}
