import SwiftUI

/// Priority, project, day, reminder, repeat, steps and notes for one task.
struct TaskDetailView: View {
    let viewModel: NotchViewModel
    private var store: TaskStore { viewModel.services.tasks }

    var body: some View {
        if let id = viewModel.selectedTaskID, let task = store.task(id) {
            TaskDetailContent(task: task, store: store, focus: {
                viewModel.services.focus.start(taskID: id)
                viewModel.step(to: .home)
            }) { viewModel.step(to: .tasks) }
        } else {
            Color.clear.onAppear { viewModel.step(to: .tasks) }
        }
    }
}

private struct TaskDetailContent: View {
    let task: TaskItem
    let store: TaskStore
    let focus: () -> Void
    let back: () -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var project = ""
    @State private var newStep = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    PrioritySelector(priority: task.priority) { value in store.update(task.id) { $0.priority = value } }
                    DayChips(day: task.day) { setDay($0) }
                    reminderRow
                    repeatMenu
                    HStack(spacing: 4) {
                        Image(systemName: "number").font(.system(size: 9, weight: .bold)).foregroundStyle(Design.tertiaryText)
                        TextField("Project", text: $project)
                            .textFieldStyle(.plain)
                            .font(Design.text(11))
                            .onSubmit(commitProject)
                            .onChange(of: project) { commitProject() }
                    }
                }
                .frame(width: 190, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    steps
                    TextField("Notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Design.text(11))
                        .lineLimit(2...4)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Design.fill))
                        .onChange(of: notes) { store.update(task.id, debounced: true) { [notes] in $0.notes = notes } }
                }
            }
        }
        .onAppear {
            title = task.title
            notes = task.notes
            project = task.project ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "chevron.left", size: 10, halo: 22, tint: Design.secondaryText, label: "Back", action: back)
            CheckButton(done: task.isDone, tint: task.priority.color) { store.toggle(task.id) }
            TextField("Task", text: $title)
                .textFieldStyle(.plain)
                .font(Design.text(14, .semibold))
                .onChange(of: title) {
                    let value = title.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { return }
                    store.update(task.id, debounced: true) { $0.title = value }
                }
            IconButton(symbol: "timer", size: 10, halo: 22, tint: .orange, label: "Focus on this", action: focus)
            IconButton(symbol: "trash", size: 10, halo: 22, tint: .red.opacity(0.85), label: "Delete") {
                store.delete(task.id)
                back()
            }
        }
    }

    private var reminderRow: some View {
        HStack(spacing: 6) {
            Image(systemName: task.due == nil ? "bell.slash" : "bell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(task.due == nil ? Design.tertiaryText : .yellow)
                .frame(width: 12)
            if let due = task.due {
                DatePicker("", selection: Binding(get: { due }, set: { value in store.update(task.id) { $0.due = value } }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(Design.text(11))
                    .fixedSize()
                IconButton(symbol: "xmark", size: 8, halo: 18, tint: Design.tertiaryText, label: "Remove reminder") {
                    store.update(task.id) { $0.due = nil }
                }
            } else {
                Button("Remind me") {
                    let base = task.day ?? Calendar.current.startOfDay(for: Date())
                    let hour = Calendar.current.component(.hour, from: Date()) + 1
                    let due = Calendar.current.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: base)
                    store.update(task.id) { $0.due = due }
                }
                .buttonStyle(.plain)
                .font(Design.text(11))
                .foregroundStyle(Design.secondaryText)
            }
        }
    }

    private var repeatMenu: some View {
        Menu {
            Button("Never") { store.update(task.id) { $0.repeatRule = nil } }
            Divider()
            ForEach(Self.repeatChoices(for: task.day), id: \.self) { rule in
                Button(rule.title) { store.update(task.id) { $0.repeatRule = rule } }
            }
        } label: {
            Label(task.repeatRule?.title ?? "Doesn't repeat", systemImage: "repeat")
                .font(Design.text(11))
                .foregroundStyle(task.repeatRule == nil ? Design.secondaryText : .mint)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(task.steps) { step in
                        HStack(spacing: 6) {
                            Button {
                                store.update(task.id) { item in
                                    if let index = item.steps.firstIndex(where: { $0.id == step.id }) { item.steps[index].done.toggle() }
                                }
                            } label: {
                                Image(systemName: step.done ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(step.done ? .green : Design.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            Text(step.title)
                                .font(Design.text(11))
                                .strikethrough(step.done)
                                .foregroundStyle(step.done ? Design.tertiaryText : .white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contextMenu {
                            Button("Delete step", role: .destructive) {
                                store.update(task.id) { $0.steps.removeAll { $0.id == step.id } }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 60)
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Design.tertiaryText)
                TextField("Add step", text: $newStep)
                    .textFieldStyle(.plain)
                    .font(Design.text(11))
                    .onSubmit {
                        let value = newStep.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { return }
                        store.update(task.id) { $0.steps.append(TaskStep(title: value)) }
                        newStep = ""
                    }
            }
        }
    }

    private func commitProject() {
        let value = project.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        store.update(task.id, debounced: true) { $0.project = value.isEmpty ? nil : value }
    }

    /// Changing the day keeps the reminder's time of day.
    private func setDay(_ day: Date?) {
        store.update(task.id) { item in
            item.day = day
            if let due = item.due {
                let calendar = Calendar.current
                let time = calendar.dateComponents([.hour, .minute], from: due)
                let base = day ?? calendar.startOfDay(for: Date())
                item.due = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: base)
            }
        }
    }

    static func repeatChoices(for day: Date?) -> [RepeatRule] {
        let weekday = Calendar.current.component(.weekday, from: day ?? Date())
        return [.daily, .weekdays, .weekly([weekday]), .monthly]
    }
}

private struct PrioritySelector: View {
    let priority: TaskPriority
    let set: (TaskPriority) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TaskPriority.allCases, id: \.self) { value in
                Button { withAnimation(NotchViewModel.snappy) { set(value) } } label: {
                    Image(systemName: value == .none ? "flag.slash" : "flag.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(value == priority ? (value == .none ? .white : value.color) : Design.tertiaryText)
                        .frame(width: 26, height: 20)
                        .background(Capsule().fill(value == priority ? value.color.opacity(0.22) : Design.fill))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(value.title) priority")
            }
        }
    }
}

/// Today · Tomorrow · Next week · Anytime.
struct DayChips: View {
    let day: Date?
    let set: (Date?) -> Void

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let choices: [(String, Date?)] = [
            ("Today", today),
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today)),
            ("Next week", calendar.date(byAdding: .day, value: 7, to: today)),
            ("Anytime", nil),
        ]
        HStack(spacing: 3) {
            ForEach(choices, id: \.0) { title, date in
                let selected = date == day
                Button { set(date) } label: {
                    Text(title)
                        .font(Design.text(9.5, .semibold))
                        .foregroundStyle(selected ? .black : Design.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Capsule().fill(selected ? Color.white : Design.fill))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
        .help(day.map { TaskFormat.day($0) } ?? "Anytime")
    }
}
