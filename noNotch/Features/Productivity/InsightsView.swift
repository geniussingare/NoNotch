import Charts
import SwiftUI

/// The last seven days: tasks finished, time focused, and when you get the most done.
struct InsightsView: View {
    let store: TaskStore
    let back: () -> Void

    var body: some View {
        let stats = InsightStats(data: store.data)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                IconButton(symbol: "chevron.left", size: 10, halo: 22, tint: Design.secondaryText, label: "Back", action: back)
                Text("This week").font(Design.text(13, .semibold))
                Spacer()
                Text(stats.summary)
                    .font(Design.text(10.5))
                    .foregroundStyle(Design.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 14) {
                DayBars(title: "Tasks done", total: "\(stats.tasksDone)", days: stats.days, value: \.tasks, color: .cyan, unit: { "\(Int($0)) done" })
                DayBars(title: "Focus", total: Self.duration(stats.focusSeconds), days: stats.days, value: \.focusMinutes, color: .orange, unit: { Self.duration($0 * 60) })
            }

            PeakHours(hours: stats.hours, peak: stats.peakHour)
        }
    }

    static func duration(_ seconds: Double) -> String { InsightStats.duration(seconds) }
}

/// One measure per chart: a single-hue bar per day, value on hover.
private struct DayBars: View {
    let title: String
    let total: String
    let days: [InsightStats.Day]
    let value: KeyPath<InsightStats.Day, Double>
    let color: Color
    let unit: (Double) -> String

    @State private var hovered: Date?

    init(title: String, total: String, days: [InsightStats.Day], value: KeyPath<InsightStats.Day, Int>, color: Color, unit: @escaping (Double) -> String) {
        self.init(title: title, total: total, days: days, value: \.tasksAsDouble, color: color, unit: unit)
    }

    init(title: String, total: String, days: [InsightStats.Day], value: KeyPath<InsightStats.Day, Double>, color: Color, unit: @escaping (Double) -> String) {
        self.title = title
        self.total = total
        self.days = days
        self.value = value
        self.color = color
        self.unit = unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(Design.tertiaryText)
                Spacer()
                Text(hoveredLabel ?? total)
                    .font(Design.number(11, .semibold))
                    .contentTransition(.numericText())
            }
            Chart(days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value(title, day[keyPath: value]), width: .ratio(0.5))
                    .foregroundStyle(color.opacity(hovered == nil || hovered == day.date ? 1 : 0.4))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(Design.tertiaryText)
                }
            }
            .chartOverlay { proxy in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let date: Date? = proxy.value(atX: point.x)
                            hovered = date.map { Calendar.current.startOfDay(for: $0) }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
            .frame(height: 64)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Design.fill))
    }

    private var hoveredLabel: String? {
        guard let hovered, let day = days.first(where: { $0.date == hovered }) else { return nil }
        return "\(day.date.formatted(.dateTime.weekday(.abbreviated))) · \(unit(day[keyPath: value]))"
    }
}

private extension InsightStats.Day {
    var tasksAsDouble: Double { Double(tasks) }
}

/// 24 cells, one hue light → bright by activity.
private struct PeakHours: View {
    let hours: [Double]
    let peak: Int?

    var body: some View {
        let top = max(hours.max() ?? 0, 1)
        HStack(spacing: 6) {
            Text("PEAK HOURS").font(.system(size: 9, weight: .semibold)).foregroundStyle(Design.tertiaryText)
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(hours[hour] > 0 ? Color.orange.opacity(0.2 + 0.8 * hours[hour] / top) : Design.fill)
                        .frame(height: 10)
                        .help(String(format: "%02d:00", hour))
                }
            }
            Text(peak.map { String(format: "%02d:00", $0) } ?? "—")
                .font(Design.number(10, .semibold))
                .foregroundStyle(Design.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
