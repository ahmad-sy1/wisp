import AppKit
import SwiftUI

/// Notes (board 6): recent notes on the left, a text field to write one on the right.
struct NotesTab: View {
    @ObservedObject var notes: NotesStore

    var body: some View {
        HStack(spacing: 10) {
            Card { NoteList(notes: notes) }
                .frame(width: 241)
            Card { NoteEditor(notes: notes) }
        }
    }
}

private struct NoteList: View {
    @ObservedObject var notes: NotesStore

    var body: some View {
        if notes.notes.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text("Your notes show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(notes.notes) { note in
                        NoteRow(note: note, selected: notes.editing == note.id) { notes.edit(note) }
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(note.text, forType: .string)
                                }
                                Button("Delete", role: .destructive) { notes.delete(note) }
                            }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(Self.when(note.updatedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.activeTab : hovered ? Theme.controlHover : .clear))
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Edit this note")
    }

    /// "13:50", "yesterday", "28 Oct".
    static func when(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.clockTime }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "yesterday") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private struct NoteEditor: View {
    @ObservedObject var notes: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $notes.draft)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .overlay(alignment: .topLeading) {
                    if notes.draft.isEmpty {
                        Text("Type a note…")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            HStack(spacing: 8) {
                if notes.editing != nil {
                    Button { notes.cancelEditing() } label: {
                        Label("Editing a note", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Stop editing")
                } else {
                    Text("Only on this Mac")
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Button("Save") { notes.save() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!notes.canSave)
            }
            .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

/// Right side of the tab bar on the Notes tab: "3 notes".
struct NotesToolbar: View {
    @ObservedObject var notes: NotesStore

    var body: some View {
        Text("\(notes.notes.count) notes")
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
    }
}
