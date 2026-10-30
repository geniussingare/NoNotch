import SwiftUI

/// Quick notes: a slim list on the left, the editor on the right.
struct NotesView: View {
    @Bindable var notes: NotesStore
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(notes.notes) { note in
                            NoteRow(note: note, selected: note.id == notes.selectedID) {
                                withAnimation(NotchViewModel.snappy) { notes.selectedID = note.id }
                            }
                            .contextMenu { Button("Delete") { withAnimation(NotchViewModel.spring) { notes.delete(note) } } }
                        }
                    }
                }
                IconButton(symbol: "square.and.pencil", size: 11, halo: 24, tint: Design.secondaryText) {
                    withAnimation(NotchViewModel.spring) { notes.add() }
                    editing = true
                }
                .help("New note")
            }
            .frame(width: 112)

            TextEditor(text: $draft)
                .font(Design.text(12.5))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($editing)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Design.fill))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Jot something down…")
                            .font(Design.text(12.5))
                            .foregroundStyle(Design.tertiaryText)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear { draft = notes.selected?.text ?? "" }
        .onChange(of: notes.selectedID) { draft = notes.selected?.text ?? "" }
        .onChange(of: draft) { notes.update(draft) }
    }
}

private struct NoteRow: View {
    let note: NotesStore.Note
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(Design.text(11, selected ? .semibold : .regular))
                    .lineLimit(1)
                Text(note.updated, format: .relative(presentation: .named))
                    .font(Design.text(9))
                    .foregroundStyle(Design.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Design.fill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
