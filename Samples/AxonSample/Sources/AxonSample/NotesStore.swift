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
}
