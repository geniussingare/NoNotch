import Foundation
import Observation

/// Quick notes kept in the notch. Plain text, saved as you type.
@MainActor
@Observable
final class NotesStore {
    struct Note: Identifiable, Codable, Equatable {
        var id = UUID()
        var text: String
        var updated: Date

        var title: String {
            let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            return first.trimmingCharacters(in: .whitespaces).isEmpty ? "New Note" : first
        }
    }

    private static let storageKey = "notes"

    private(set) var notes: [Note]
    var selectedID: UUID?

    init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        notes = data.flatMap { try? JSONDecoder().decode([Note].self, from: $0) } ?? []
        if notes.isEmpty { notes = [Note(text: "", updated: Date())] }
        selectedID = notes.first?.id
    }

    var selected: Note? { notes.first { $0.id == selectedID } }

    func update(_ text: String) {
        guard let index = notes.firstIndex(where: { $0.id == selectedID }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updated = Date()
        save()
    }

    func add() {
        let note = Note(text: "", updated: Date())
        notes.insert(note, at: 0)
        selectedID = note.id
        save()
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if notes.isEmpty { notes = [Note(text: "", updated: Date())] }
        if selectedID == note.id { selectedID = notes.first?.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
