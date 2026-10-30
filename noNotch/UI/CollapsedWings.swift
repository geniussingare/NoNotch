import SwiftUI

/// Compact presentation: leading and trailing content hugging the hardware notch.
struct CollapsedWings: View {
    let viewModel: NotchViewModel
    let wing: WingContent

    private var services: Services { viewModel.services }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: wing.width, alignment: .leading)
                .padding(.leading, 8)
            Spacer(minLength: viewModel.geometry.notchSize.width)
            trailing
                .frame(width: wing.width, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(height: viewModel.geometry.notchSize.height)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var leading: some View {
        switch wing {
        case .media:
            MediaThumb(media: services.media, height: 18)
        case .pomodoro:
            ProgressRing(pomodoro: services.pomodoro, size: 14, lineWidth: 2)
        case .activity(let activity):
            ActivityLeading(activity: activity)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch wing {
        case .media:
            Waveform(playing: services.media.isPlaying, palette: services.media.palette, bars: 4)
                .frame(width: 16, height: 12)
        case .pomodoro:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Format.time(services.pomodoro.remaining(at: context.date)))
                    .font(Design.number(11))
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(countsDown: true))
            }
        case .activity(let activity):
            ActivityTrailing(activity: activity, accent: viewModel.accent)
        }
    }
}

struct MediaThumb: View {
    let media: NowPlayingService
    let height: CGFloat

    var body: some View {
        let width = media.isVideo ? height * 16 / 9 : height
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = media.sourceIcon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "music.note").font(.system(size: height * 0.55, weight: .bold))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.28, style: .continuous))
        .scaleEffect(media.isPlaying ? 1 : 0.88)
        .animation(NotchViewModel.spring, value: media.isPlaying)
    }
}

private struct ActivityLeading: View {
    let activity: LiveActivity

    var body: some View {
        switch activity {
        case .hud(let kind, let value):
            Image(systemName: hudSymbol(kind), variableValue: value)
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        case .power(_, _, let plugged):
            Image(systemName: plugged ? "bolt.fill" : "powerplug.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(plugged ? .green : .white.opacity(0.7))
                .symbolEffect(.bounce, value: plugged)
        case .lowBattery:
            Image(systemName: "battery.25percent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .bluetooth(_, let symbol, let connected):
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(connected ? .white : .white.opacity(0.5))
                .symbolEffect(.bounce, value: connected)
        case .download(_, _, let finished, _):
            Image(systemName: finished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(finished ? .green : .blue)
                .symbolEffect(.pulse, isActive: !finished)
                .contentTransition(.symbolEffect(.replace))
        case .event:
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        case .notification:
            // Shown as a full banner by NotchRootView instead of wings.
            EmptyView()
        case .eyeBreak:
            Image(systemName: "eye")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan)
                .symbolEffect(.pulse)
        case .timerFinished:
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, value: true)
        }
    }

    private func hudSymbol(_ kind: HUDKind) -> String {
        switch kind {
        case .volume(let muted): muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: "sun.max.fill"
        }
    }
}

private struct ActivityTrailing: View {
    let activity: LiveActivity
    let accent: Color

    var body: some View {
        switch activity {
        case .hud(_, let value):
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(5, proxy.size.width * value))
                }
            }
            .frame(width: 44, height: 4)
            .animation(NotchViewModel.snappy, value: value)
        case .power(let level, _, let plugged):
            label("\(level)%", color: plugged ? .green : .white)
        case .lowBattery(let level):
            label("\(level)%", color: .red)
        case .bluetooth(let name, _, let connected):
            VStack(alignment: .trailing, spacing: 0) {
                Text(name).font(Design.text(10, .medium)).lineLimit(1)
                Text(connected ? "Connected" : "Disconnected")
                    .font(Design.text(9))
                    .foregroundStyle(Design.secondaryText)
            }
        case .download(_, let bytes, let finished, _):
            label(finished ? "Done" : Format.bytes(bytes), color: finished ? .green : .white)
        case .event(let title, let minutes):
            VStack(alignment: .trailing, spacing: 0) {
                Text(title).font(Design.text(10, .medium)).lineLimit(1)
                Text(minutes <= 0 ? "Now" : "in \(minutes) min")
                    .font(Design.text(9))
                    .foregroundStyle(.red)
            }
        case .notification:
            EmptyView()
        case .eyeBreak(let until):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Look away").font(Design.text(10, .medium))
                    Text("\(max(Int(until.timeIntervalSince(context.date).rounded()), 0))s")
                        .font(Design.number(9))
                        .foregroundStyle(.cyan)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        case .timerFinished(let message):
            Text(message).font(Design.text(10, .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Design.number(11))
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }
}

struct ProgressRing: View {
    let pomodoro: PomodoroTimer
    let size: CGFloat
    var lineWidth: CGFloat = 2.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: pomodoro.progress(at: context.date))
                    .stroke(pomodoro.phase == .shortBreak ? Color.green : .orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}
