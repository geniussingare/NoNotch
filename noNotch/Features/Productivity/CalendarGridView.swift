import EventKit
import SwiftUI

/// Month grid with event dots; pick a day to see its agenda.
struct CalendarGridView: View {
    let calendar: CalendarService
    let onBack: () -> Void

    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var direction: Edge = .trailing

    private let cal = Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                header
                grid
                    .id(month)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction).combined(with: .opacity),
                        removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(width: 210)
            .clipped()

            agenda
        }
        .onAppear { calendar.loadMonth(containing: month) }
        .onChange(of: month) { calendar.loadMonth(containing: month) }
    }

    private var header: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "chevron.left", size: 9, halo: 20, tint: Design.secondaryText, action: onBack)
                .help("Back")
            Text(month, format: .dateTime.month(.wide).year())
                .font(Design.text(12, .semibold))
            Spacer()
            IconButton(symbol: "chevron.up", size: 9, halo: 20, tint: Design.secondaryText) { shift(-1) }
            IconButton(symbol: "chevron.down", size: 9, halo: 20, tint: Design.secondaryText) { shift(1) }
        }
    }

    private var grid: some View {
        let days = monthDays()
        let symbols = cal.veryShortWeekdaySymbols
        let shifted = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(Array(shifted.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Design.text(8.5, .semibold))
                        .foregroundStyle(Design.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date: day,
                            isToday: cal.isDateInToday(day),
                            isSelected: cal.isDate(day, inSameDayAs: selected),
                            colors: calendar.monthEvents[cal.startOfDay(for: day)]?.prefix(3).map(\.color) ?? []
                        ) {
                            withAnimation(NotchViewModel.snappy) { selected = cal.startOfDay(for: day) }
                        }
                    } else {
                        Color.clear.frame(height: 18)
                    }
                }
            }
        }
    }

    private var agenda: some View {
        let events = calendar.monthEvents[selected] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text(selected, format: .dateTime.weekday(.wide).day().month())
                .font(Design.text(11.5, .semibold))
                .foregroundStyle(Design.secondaryText)
            if !calendar.authorized {
                Text("Allow Calendar access in Permissions.")
                    .font(Design.text(11))
                    .foregroundStyle(Design.tertiaryText)
            } else if events.isEmpty {
                Text("No events")
                    .font(Design.text(11.5))
                    .foregroundStyle(Design.tertiaryText)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(events) { event in
                            HStack(spacing: 7) {
                                Capsule().fill(Color(nsColor: event.color)).frame(width: 3, height: 24)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(event.title).font(Design.text(11.5, .medium)).lineLimit(1)
                                    Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                                        .font(Design.text(10))
                                        .foregroundStyle(Design.tertiaryText)
                                }
                                Spacer(minLength: 0)
                                if event.meetingURL != nil {
                                    IconButton(symbol: "video.fill", size: 10, halo: 22, tint: .green) { calendar.join(event) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(selected)
        .transition(.opacity)
    }

    private func shift(_ months: Int) {
        direction = months > 0 ? .trailing : .leading
        withAnimation(NotchViewModel.spring) {
            month = cal.date(byAdding: .month, value: months, to: month) ?? month
        }
    }

    /// Leading blanks then each day of the month.
    private func monthDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let blanks = (weekday - cal.firstWeekday + 7) % 7
        let days = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: blanks) + days.map(Optional.some)
    }
}

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let colors: [NSColor]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(Design.number(10, isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? .black : (isToday ? .red : .white))
                    .frame(width: 20, height: 16)
                    .background(Circle().fill(isSelected ? Color.white : .clear).frame(width: 18, height: 18))
                HStack(spacing: 1.5) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(Color(nsColor: color)).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
