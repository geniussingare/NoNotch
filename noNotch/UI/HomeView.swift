import SwiftUI

/// Glance row of cards the user can show, hide, resize and reorder (Settings → Home).
struct HomeView: View {
    let viewModel: NotchViewModel
    private var services: Services { viewModel.services }
    @AppStorage(SettingsKey.homeCards) private var layout = Data()

    var body: some View {
        let cards = HomeCard.load().filter(\.visible)
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.kind) { index, card in
                if index > 0 {
                    Divider().overlay(Design.hairline).padding(.vertical, 6).padding(.horizontal, 14)
                }
                cardView(card)
                    .frame(width: card.width, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .id(layout)
    }

    @ViewBuilder
    private func cardView(_ card: HomeCard) -> some View {
        switch card.kind {
        case .clock:
            ClockColumn(weather: services.weather) { viewModel.step(to: .insights) }
        case .agenda:
            AgendaColumn(calendar: services.calendar, tasks: services.tasks, openCalendar: { viewModel.step(to: .calendar) }, openTasks: { viewModel.step(to: .tasks) })
        case .focus:
            FocusColumn(timer: services.focus, tasks: services.tasks, wide: card.wide) { viewModel.step(to: .tasks) }
        case .tasks:
            TodayCard(store: services.tasks, open: { viewModel.showTask($0) }, openAll: { viewModel.step(to: .tasks) })
        }
    }
}

private struct ClockColumn: View {
    let weather: WeatherService
    let openInsights: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(Design.number(30, .semibold))
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(Design.text(11.5))
                        .foregroundStyle(Design.secondaryText)
                    IconButton(symbol: "chart.bar.xaxis", size: 9, halo: 18, tint: Design.tertiaryText, label: "Insights", action: openInsights)
                        .frame(width: 18, height: 14)
                }
                if let now = weather.current {
                    HStack(spacing: 4) {
                        Image(systemName: now.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 11))
                        Text(weather.format(now.temperature))
                            .font(Design.number(11.5, .semibold))
                        Text("\(weather.format(now.high)) / \(weather.format(now.low))")
                            .font(Design.number(10, .regular))
                            .foregroundStyle(Design.tertiaryText)
                    }
                    .padding(.top, 2)
                    .help(now.summary)
                }
            }
        }
        .fixedSize()
    }
}

private struct AgendaColumn: View {
    let calendar: CalendarService
    let tasks: TaskStore
    let openCalendar: () -> Void
    let openTasks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            event
                .contentShape(Rectangle())
                .onTapGesture(perform: openCalendar)
                .help("Open calendar")
            taskLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Next open task, preferring the soonest reminder.
    @ViewBuilder
    private var taskLine: some View {
        let open = tasks.today
        let next = open.filter { $0.due != nil }.min { $0.due! < $1.due! } ?? open.first
        if let next {
            Button(action: openTasks) {
                HStack(spacing: 5) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Design.tertiaryText)
                    Text(next.title)
                        .font(Design.text(11, .medium))
                        .lineLimit(1)
                    if let due = next.due {
                        Text(due.formatted(date: .omitted, time: .shortened))
                            .font(Design.number(10, .medium))
                            .foregroundStyle(.yellow)
                    }
                    if open.count > 1 {
                        Text("+\(open.count - 1)")
                            .font(Design.number(9.5, .semibold))
                            .foregroundStyle(Design.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open tasks")
        }
    }

    private var event: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("AGENDA")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Design.tertiaryText)
            if !calendar.authorized {
                Button("Connect Calendar", action: calendar.requestAccess)
                    .buttonStyle(PillButtonStyle(tint: Design.fill))
            } else if let event = calendar.next {
                HStack(spacing: 6) {
                    Capsule().fill(Color(nsColor: event.color)).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(Design.text(12.5, .semibold))
                            .lineLimit(1)
                        TimelineView(.everyMinute) { context in
                            Text(relative(event, now: context.date))
                                .font(Design.text(11))
                                .foregroundStyle(Design.secondaryText)
                        }
                    }
                }
                if event.meetingURL != nil {
                    Button { calendar.join(event) } label: { Label("Join", systemImage: "video.fill") }
                        .buttonStyle(PillButtonStyle(tint: .green))
                }
            } else {
                Text("Nothing else today")
                    .font(Design.text(12.5, .medium))
                    .foregroundStyle(Design.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relative(_ event: CalendarService.Event, now: Date) -> String {
        if event.start <= now { return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        return minutes < 60 ? "in \(minutes) min" : event.start.formatted(date: .omitted, time: .shortened)
    }
}

private struct FocusColumn: View {
    let timer: FocusTimer
    let tasks: TaskStore
    let wide: Bool
    let addTask: () -> Void
    @AppStorage(SettingsKey.focusClockStyle) private var style = SettingsDefaults.focusClockStyle

    private var linkedTask: TaskItem? { timer.taskID.flatMap(tasks.task) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                clock
                VStack(spacing: 0) {
                    IconButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", size: 12, halo: 26,
                               label: timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Start focus"),
                               action: timer.startOrPause)
                    if timer.isActive {
                        IconButton(symbol: "arrow.counterclockwise", size: 10, halo: 22, tint: Design.tertiaryText, label: "Stop", action: timer.reset)
                            .transition(.opacity)
                    } else {
                        IconButton(symbol: timer.mode == .countdown ? "timer" : "stopwatch", size: 10, halo: 22, tint: Design.tertiaryText,
                                   label: "Switch to \(timer.mode == .countdown ? "stopwatch" : "timer")") {
                            withAnimation(NotchViewModel.snappy) { timer.mode = timer.mode == .countdown ? .stopwatch : .countdown }
                        }
                    }
                }
                if wide, timer.isActive, timer.mode == .countdown || timer.phase == .shortBreak {
                    addFive
                }
            }
            if !wide, timer.isActive, timer.mode == .countdown || timer.phase == .shortBreak {
                addFive
            } else {
                taskLink
            }
        }
        .animation(NotchViewModel.spring, value: timer.isActive)
        .help(timer.phase.title)
    }

    @ViewBuilder
    private var clock: some View {
        switch style {
        case .ring:
            ZStack {
                ProgressRing(timer: timer, size: 46, lineWidth: 3.5)
                time(10.5)
            }
        case .digital:
            VStack(alignment: .leading, spacing: 0) {
                time(20)
                Text(timer.isPaused ? "PAUSED" : timer.phase.title.uppercased())
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(timer.phase == .shortBreak ? .green : .orange)
            }
        case .minimal:
            time(16).foregroundStyle(timer.isActive ? (timer.phase == .shortBreak ? Color.green : .orange) : .white)
        }
    }

    private func time(_ size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Format.time(timer.display(at: context.date)))
                .font(Design.number(size, .semibold))
                .contentTransition(.numericText(countsDown: timer.mode == .countdown))
        }
    }

    private var addFive: some View {
        Button("+5 min", action: timer.addFiveMinutes)
            .buttonStyle(PillButtonStyle(tint: Design.fill))
            .lineLimit(1)
            .fixedSize()
    }

    /// Pick what this session is for, or invite the first task.
    @ViewBuilder
    private var taskLink: some View {
        let today = tasks.today
        if today.isEmpty, linkedTask == nil {
            Button(action: addTask) {
                Label("Add your first task", systemImage: "plus.circle.fill")
                    .font(Design.text(9.5, .semibold))
                    .foregroundStyle(Design.secondaryText)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button("No task") { timer.focus(on: nil) }
                Divider()
                ForEach(today.prefix(12)) { task in
                    Button(task.title) { timer.focus(on: task.id) }
                }
            } label: {
                Text(linkedTask?.title ?? "Focus on…")
                    .font(Design.text(9.5, .medium))
                    .foregroundStyle(linkedTask == nil ? Design.tertiaryText : Design.secondaryText)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Top few tasks for today with quick check-off.
private struct TodayCard: View {
    let store: TaskStore
    let open: (UUID) -> Void
    let openAll: () -> Void

    var body: some View {
        let tasks = store.today
        VStack(alignment: .leading, spacing: 2) {
            Button(action: openAll) {
                HStack(spacing: 4) {
                    Text("TODAY").font(.system(size: 9, weight: .semibold))
                    Text("\(tasks.count)").font(Design.number(9, .semibold))
                }
                .foregroundStyle(Design.tertiaryText)
            }
            .buttonStyle(.plain)
            if tasks.isEmpty {
                Text("All clear").font(Design.text(12, .medium)).foregroundStyle(Design.secondaryText)
            }
            ForEach(tasks.prefix(4)) { task in
                HStack(spacing: 2) {
                    CheckButton(done: task.isDone, tint: task.priority.color) {
                        withAnimation(NotchViewModel.spring) { store.toggle(task.id) }
                    }
                    Text(task.title)
                        .font(Design.text(11.5, .medium))
                        .lineLimit(1)
                        .onTapGesture { open(task.id) }
                }
                .frame(height: 20)
                .transition(.opacity)
            }
        }
        .animation(NotchViewModel.spring, value: tasks.map(\.id))
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.text(10.5, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .contentShape(Capsule())
            .glassSurface(Capsule(), tint: tint, interactive: true)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(NotchViewModel.snappy, value: configuration.isPressed)
    }
}
