import SwiftUI

/// Plan ahead: a strip of the coming week, the selected day's tasks and a composer for that day.
struct UpcomingView: View {
    let viewModel: NotchViewModel
    private var store: TaskStore { viewModel.services.tasks }

    /// `nil` selects "Later" (everything past the strip).
    @State private var selected: Date? = TaskFormat.tomorrow

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", size: 10, halo: 22, tint: Design.secondaryText, label: "Back") {
                    viewModel.step(to: .tasks)
                }
                DayStrip(days: days, selected: $selected, count: count(on:))
            }

            TaskComposer(
                store: store,
                placeholder: selected.map { "Add to \(TaskFormat.day($0))" } ?? "Add a task with a date",
                defaultDay: selected
            )
            .id(selected)

            let tasks = selected.map { store.tasks(on: $0) } ?? later
            if tasks.isEmpty {
                Text(selected == nil ? "Nothing planned further out." : "Nothing planned. Add something above.")
                    .font(Design.text(11))
                    .foregroundStyle(Design.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TaskList(tasks: tasks, store: store, showsDay: selected == nil) { viewModel.showTask($0) }
            }
        }
    }

    private var later: [TaskItem] {
        guard let last = days.last else { return [] }
        return store.upcoming.filter { ($0.day ?? .distantPast) > last }
    }

    private func count(on day: Date?) -> Int {
        day.map { store.tasks(on: $0).count } ?? later.count
    }
}

private struct DayStrip: View {
    let days: [Date]
    @Binding var selected: Date?
    let count: (Date?) -> Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days, id: \.self) { day in
                cell(top: Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)),
                     bottom: day.formatted(.dateTime.day()), value: day)
            }
            cell(top: "Later", bottom: "…", value: nil)
        }
    }

    private func cell(top: String, bottom: String, value: Date?) -> some View {
        let isSelected = selected == value
        let tasks = count(value)
        return Button {
            withAnimation(NotchViewModel.spring) { selected = value }
        } label: {
            VStack(spacing: 0) {
                Text(top).font(Design.text(8.5, .semibold)).foregroundStyle(isSelected ? .white : Design.tertiaryText)
                Text(bottom).font(Design.number(12, .semibold))
                Circle()
                    .fill(tasks > 0 ? Color.cyan : .clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(width: 42, height: 38)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.clear)
                        .glassSurface(RoundedRectangle(cornerRadius: 10, style: .continuous), tint: .white.opacity(0.14))
                        .matchedGeometryEffect(id: "day", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(tasks == 1 ? "1 task" : "\(tasks) tasks")
    }
}
