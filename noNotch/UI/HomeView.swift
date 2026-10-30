import SwiftUI

/// Glance row: time, what's next, focus timer. No nested cards.
struct HomeView: View {
    let viewModel: NotchViewModel
    private var services: Services { viewModel.services }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ClockColumn(weather: services.weather)
            Divider().overlay(Design.hairline).padding(.vertical, 6).padding(.horizontal, 14)
            NextEventColumn(calendar: services.calendar)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.step(to: .calendar) }
                .help("Open calendar")
            Divider().overlay(Design.hairline).padding(.vertical, 6).padding(.horizontal, 14)
            FocusColumn(pomodoro: services.pomodoro)
        }
    }
}

private struct ClockColumn: View {
    let weather: WeatherService

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(Design.number(30, .semibold))
                    .contentTransition(.numericText())
                Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(Design.text(11.5))
                    .foregroundStyle(Design.secondaryText)
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

private struct NextEventColumn: View {
    let calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("UP NEXT")
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
    let pomodoro: PomodoroTimer

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                ProgressRing(pomodoro: pomodoro, size: 46, lineWidth: 3.5)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.time(pomodoro.remaining(at: context.date)))
                        .font(Design.number(10.5, .semibold))
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            VStack(spacing: 0) {
                IconButton(symbol: pomodoro.isRunning ? "pause.fill" : "play.fill", size: 12, halo: 26, action: pomodoro.startOrPause)
                if pomodoro.isActive {
                    IconButton(symbol: "arrow.counterclockwise", size: 10, halo: 22, tint: Design.tertiaryText, action: pomodoro.reset)
                        .transition(.opacity)
                }
            }
        }
        .fixedSize()
        .animation(NotchViewModel.spring, value: pomodoro.isActive)
        .help(pomodoro.phase.title)
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
