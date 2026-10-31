import SwiftUI

/// Today's tasks: a natural-language composer, a To do / Done switch and a reorderable list.
struct TasksView: View {
    let viewModel: NotchViewModel
    private var store: TaskStore { viewModel.services.tasks }
    @State private var showCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TaskComposer(store: store, placeholder: "Add a task — try “call mom tomorrow 5pm #family”")
                DoneSwitch(showCompleted: $showCompleted, open: store.today.count)
                IconButton(symbol: "calendar.day.timeline.left", size: 11, halo: 24, tint: Design.secondaryText, label: "Upcoming") {
                    viewModel.step(to: .upcoming)
                }
            }

            let tasks = showCompleted ? store.completed : store.today
            if tasks.isEmpty {
                TasksEmptyState(showCompleted: showCompleted)
            } else {
                TaskList(tasks: tasks, store: store) { viewModel.showTask($0) }
            }
        }
    }
}

/// Scrolling, drag-to-reorder list of task rows.
struct TaskList: View {
    let tasks: [TaskItem]
    let store: TaskStore
    var showsDay = false
    let open: (UUID) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(tasks) { task in
                    TaskRow(task: task, store: store, showsDay: showsDay) { open(task.id) }
                        .draggable(task.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            withAnimation(NotchViewModel.spring) { store.move(id, before: task.id) }
                            return true
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                }
            }
            .animation(NotchViewModel.spring, value: tasks.map(\.id))
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    let store: TaskStore
    var showsDay = false
    let open: () -> Void

    @State private var hovering = false
    @State private var renaming = false
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            CheckButton(done: task.isDone, tint: task.priority.color) {
                withAnimation(NotchViewModel.spring) { store.toggle(task.id) }
            }

            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    TextField("Task", text: $title)
                        .textFieldStyle(.plain)
                        .font(Design.text(12.5, .medium))
                        .focused($titleFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { renaming = false }
                        .onChange(of: titleFocused) { _, focused in if !focused { commitRename() } }
                } else {
                    Text(task.title)
                        .font(Design.text(12.5, .medium))
                        .strikethrough(task.isDone, color: Design.tertiaryText)
                        .foregroundStyle(task.isDone ? Design.tertiaryText : .white)
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: beginRename)
                }
                TaskMeta(task: task, showsDay: showsDay)
                if let suggestion = task.suggestion, !task.isDone {
                    SuggestionChip(suggestion: suggestion) { accept in
                        withAnimation(NotchViewModel.spring) {
                            store.update(task.id) { item in
                                if accept {
                                    item.priority = suggestion.priority ?? item.priority
                                    item.project = suggestion.project ?? item.project
                                }
                                item.suggestion = nil
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering && !renaming {
                IconButton(symbol: "info.circle", size: 11, halo: 22, tint: Design.secondaryText, label: "Details", action: open)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Design.fill : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(NotchViewModel.snappy, value: hovering)
        .contextMenu {
            Button("Details…", action: open)
            Button("Rename", action: beginRename)
            Divider()
            Button("Today") { store.update(task.id) { $0.day = Calendar.current.startOfDay(for: Date()) } }
            Button("Tomorrow") { store.update(task.id) { $0.day = TaskFormat.tomorrow } }
            Divider()
            Button("Delete", role: .destructive) { withAnimation(NotchViewModel.spring) { store.delete(task.id) } }
        }
    }

    private func beginRename() {
        title = task.title
        renaming = true
        titleFocused = true
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != task.title { store.update(task.id) { $0.title = trimmed } }
    }
}

/// Small grey line under a task: day, time, repeat, steps, project.
struct TaskMeta: View {
    let task: TaskItem
    var showsDay = false

    var body: some View {
        let parts = pieces
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(parts, id: \.text) { piece in
                    HStack(spacing: 2) {
                        Image(systemName: piece.symbol).font(.system(size: 8, weight: .semibold))
                        Text(piece.text).font(Design.text(9.5))
                    }
                    .foregroundStyle(piece.color)
                }
            }
            .lineLimit(1)
        }
    }

    private struct Piece {
        let symbol: String
        let text: String
        var color: Color = Design.tertiaryText
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        let now = Date()
        if let due = task.due {
            let overdue = !task.isDone && due < now
            let text = showsDay || !Calendar.current.isDateInToday(due)
                ? "\(TaskFormat.day(due)) \(due.formatted(date: .omitted, time: .shortened))"
                : due.formatted(date: .omitted, time: .shortened)
            result.append(Piece(symbol: "bell.fill", text: text, color: overdue ? .red.opacity(0.9) : Design.tertiaryText))
        } else if let day = task.day, showsDay || day < Calendar.current.startOfDay(for: now) {
            result.append(Piece(symbol: "calendar", text: TaskFormat.day(day)))
        }
        if let rule = task.repeatRule { result.append(Piece(symbol: "repeat", text: rule.title)) }
        if !task.steps.isEmpty {
            result.append(Piece(symbol: "checklist", text: "\(task.steps.filter(\.done).count)/\(task.steps.count)"))
        }
        if let project = task.project { result.append(Piece(symbol: "number", text: project, color: TaskFormat.color(for: project))) }
        return result
    }
}

/// Apple Intelligence's guess: tap to apply, × to dismiss.
private struct SuggestionChip: View {
    let suggestion: TaskSuggestion
    let resolve: (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button { resolve(true) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles").font(.system(size: 8, weight: .bold))
                    if let priority = suggestion.priority, priority != .none {
                        Text(priority.title).foregroundStyle(priority.color)
                    }
                    if let project = suggestion.project {
                        Text("#\(project)").foregroundStyle(TaskFormat.color(for: project))
                    }
                }
                .font(Design.text(9.5, .semibold))
            }
            .buttonStyle(.plain)
            .help("Apply suggestion")
            Button { resolve(false) } label: {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .foregroundStyle(Design.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(LinearGradient(colors: [.purple.opacity(0.25), .cyan.opacity(0.18)], startPoint: .leading, endPoint: .trailing)))
    }
}

/// Round checkbox that fills with a little bounce.
struct CheckButton: View {
    let done: Bool
    var tint: Color = Design.tertiaryText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(done ? Color.clear : tint, lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            .frame(width: Design.minTarget - 6, height: Design.minTarget - 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(done ? "Mark as not done" : "Mark as done"))
        .animation(NotchViewModel.spring, value: done)
    }
}

/// Glass field that understands dates, repeats, priority and #projects, previewed as chips.
struct TaskComposer: View {
    let store: TaskStore
    var placeholder = "Add a task"
    var defaultDay: Date? = nil

    @State private var draft = ""
    @State private var dictationBase = ""
    @State private var owner = UUID().uuidString
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = TaskParser.parse(draft)
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Design.tertiaryText)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(Design.text(12))
                .focused($focused)
                .onSubmit(submit)
            if !draft.isEmpty, parsed.hasMetadata {
                ParsedChips(parsed: parsed)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
            DictationButton(dictation: .shared, owner: owner) { text in
                draft = dictationBase.isEmpty ? text : dictationBase + " " + text
            }
            .simultaneousGesture(TapGesture().onEnded { dictationBase = draft })
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .glassSurface(Capsule(), tint: .white.opacity(focused ? 0.1 : 0.04))
        .animation(NotchViewModel.snappy, value: parsed.hasMetadata && !draft.isEmpty)
    }

    private func submit() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(NotchViewModel.spring) { _ = store.add(draft, defaultDay: defaultDay) }
        draft = ""
        focused = true
    }
}

/// What the composer understood, shown while typing.
struct ParsedChips: View {
    let parsed: ParsedTask

    var body: some View {
        HStack(spacing: 3) {
            if let due = parsed.due {
                chip("bell.fill", "\(TaskFormat.day(due)) \(due.formatted(date: .omitted, time: .shortened))", .yellow)
            } else if let day = parsed.day {
                chip("calendar", TaskFormat.day(day), .cyan)
            }
            if parsed.repeatRule != nil { chip("repeat", nil, .mint) }
            if let priority = parsed.priority { chip("flag.fill", nil, priority.color) }
            if let project = parsed.project { chip("number", project, TaskFormat.color(for: project)) }
        }
        .fixedSize()
    }

    private func chip(_ symbol: String, _ text: String?, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            if let text { Text(text).font(Design.text(9.5, .semibold)) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// Compact "To do · Done" switch with a gliding pill.
private struct DoneSwitch: View {
    @Binding var showCompleted: Bool
    let open: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            segment("To do \(open)", selected: !showCompleted) { showCompleted = false }
            segment("Done", selected: showCompleted) { showCompleted = true }
        }
        .padding(2)
        .background(Capsule().fill(Design.fill))
        .fixedSize()
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(NotchViewModel.spring, action)
        } label: {
            Text(title)
                .font(Design.text(10, .semibold))
                .foregroundStyle(selected ? .white : Design.tertiaryText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background {
                    if selected {
                        Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TasksEmptyState: View {
    let showCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: showCompleted ? "checkmark.seal" : "sun.max")
                .font(.system(size: Design.Icon.hero, weight: .light))
                .foregroundStyle(Design.tertiaryText)
            Text(showCompleted ? "Nothing finished yet" : "A clear day")
                .font(Design.text(12.5, .semibold))
            Text(showCompleted ? "Completed tasks land here." : "Type above. Dates, “every week”, !high and #project all work.")
                .font(Design.text(10.5))
                .foregroundStyle(Design.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Formatting

enum TaskFormat {
    static var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
    }

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if (0..<7).contains(days) { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Stable colour per project name.
    static func color(for project: String) -> Color {
        let palette: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .indigo, .purple, .teal]
        let hash = project.lowercased().unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

extension TaskPriority {
    var color: Color {
        switch self {
        case .none: Design.tertiaryText
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}
