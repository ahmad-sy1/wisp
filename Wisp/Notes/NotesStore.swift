import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var updatedAt: Date

    /// The first line, for the list.
    var title: String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
    }
}

/// Quick notes (board 6), newest first, stored as JSON on this Mac only.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [Note]
    /// What is being typed; kept while the notch closes, so nothing is lost.
    @Published var draft = ""
    /// The note being edited, or nil for a new one.
    @Published private(set) var editing: Note.ID?

    private static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/wisp/notes.json")
    }

    private init() {
        notes = (try? Data(contentsOf: Self.file))
            .flatMap { try? JSONDecoder().decode([Note].self, from: $0) } ?? []
    }

    var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Saves the draft as a new note, or over the one being edited; either goes to the top.
    func save() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let editing { notes.removeAll { $0.id == editing } }
        notes.insert(Note(id: editing ?? UUID(), text: text, updatedAt: .now), at: 0)
        draft = ""
        editing = nil
        write()
    }

    func edit(_ note: Note) {
        editing = note.id
        draft = note.text
    }

    func cancelEditing() {
        editing = nil
        draft = ""
    }

    func delete(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if editing == note.id { cancelEditing() }
        write()
    }

    private func write() {
        let file = Self.file
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(notes) else { return }
        FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
    }
}
