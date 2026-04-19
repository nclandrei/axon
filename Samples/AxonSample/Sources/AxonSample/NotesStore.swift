import SwiftUI
import Combine

final class Note: Identifiable, ObservableObject {
    let id = UUID()
    @Published var title: String
    @Published var body: String
    @Published var isDirty: Bool

    init(title: String = "Untitled", body: String = "") {
        self.title = title
        self.body = body
        self.isDirty = false
    }
}

final class NotesStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID? = nil

    func createNote() {
        let note = Note()
        notes.append(note)
        selectedID = note.id
    }

    var selectedNote: Note? {
        guard let id = selectedID else { return nil }
        return notes.first(where: { $0.id == id })
    }

    func save() {
        selectedNote?.isDirty = false
    }

    func deleteSelected() {
        guard let id = selectedID, let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: idx)
        selectedID = notes.first?.id
    }

    @Published var showUnsavedSheet: Bool = false

    /// Called when the user attempts to close a dirty note. Returns true if the
    /// action should proceed immediately; false if the sheet will intercept.
    func attemptClose() -> Bool {
        if let note = selectedNote, note.isDirty {
            showUnsavedSheet = true
            return false
        }
        // Clean: proceed as a regular delete.
        deleteSelected()
        return true
    }

    func dismissSheetSave() {
        save()
        showUnsavedSheet = false
        deleteSelected()
    }

    func dismissSheetDontSave() {
        showUnsavedSheet = false
        deleteSelected()
    }

    func dismissSheetCancel() {
        showUnsavedSheet = false
    }
}
