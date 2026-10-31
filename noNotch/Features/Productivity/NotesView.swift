import SwiftUI

/// Notepad: today's page pinned on top, saved notes below, the editor on the right.
/// ⌘↩ turns the current line into a task.
struct NotesView: View {
    @Bindable var notes: NotesStore
    let tasks: TaskStore

    /// `nil` shows today's daily page.
    @State private var selection: UUID?
    @State private var draft = ""
    @State private var toast: String?
    @State private var dictationBase = ""

    private var todayKey: String { StoreData.noteKey(for: Date()) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        DailyRow(selected: selection == nil) { select(nil) }
                        ForEach(notes.notes) { note in
                            NoteRow(note: note, selected: note.id == selection) { select(note.id) }
                                .contextMenu { Button("Delete") { withAnimation(NotchViewModel.spring) { notes.delete(note); select(nil) } } }
                        }
                    }
                }
                IconButton(symbol: "square.and.pencil", size: 11, halo: 24, tint: Design.secondaryText, label: "New note") {
                    withAnimation(NotchViewModel.spring) { notes.add() }
                    select(notes.selectedID)
                }
            }
            .frame(width: 112)

            NoteEditor(text: $draft) { line in
                guard tasks.add(line) != nil else { return false }
                withAnimation(NotchViewModel.snappy) { toast = "Added to Tasks" }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(NotchViewModel.snappy) { toast = nil }
                }
                return true
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Design.fill))
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(selection == nil ? "Today’s page. ⌘↩ turns a line into a task." : "Jot something down…")
                        .font(Design.text(12.5))
                        .foregroundStyle(Design.tertiaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                DictationButton(dictation: .shared, owner: "notes") { text in
                    let separator = dictationBase.isEmpty || dictationBase.hasSuffix("\n") ? "" : "\n"
                    draft = dictationBase + separator + text
                }
                .simultaneousGesture(TapGesture().onEnded { dictationBase = draft })
                .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if let toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(Design.text(10, .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .glassSurface(Capsule())
                        .padding(6)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .onAppear { load() }
        .onChange(of: draft) { save() }
    }

    private func select(_ id: UUID?) {
        withAnimation(NotchViewModel.snappy) { selection = id }
        notes.selectedID = id ?? notes.selectedID
        load()
    }

    private func load() {
        draft = selection == nil ? (tasks.data.dailyNotes[todayKey] ?? "") : (notes.selected?.text ?? "")
    }

    private func save() {
        if selection == nil {
            let key = todayKey, text = draft
            guard tasks.data.dailyNotes[key] ?? "" != text else { return }
            tasks.mutate(debounced: true) { $0.dailyNotes[key] = text.isEmpty ? nil : text }
        } else {
            notes.update(draft)
        }
    }
}

private struct DailyRow: View {
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today").font(Design.text(11, selected ? .semibold : .regular))
                    Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(Design.text(9))
                        .foregroundStyle(Design.tertiaryText)
                }
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
