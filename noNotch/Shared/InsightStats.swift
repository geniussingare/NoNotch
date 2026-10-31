import Foundation

/// Seven-day summary shared by the Insights page and the MCP helper.
struct InsightStats {
    struct Day: Identifiable {
        let date: Date
        var tasks = 0
        var focusMinutes = 0.0
        var id: Date { date }
    }

    var days: [Day] = []
    /// Activity per hour of day (focus minutes + 10 per finished task).
    var hours = Array(repeating: 0.0, count: 24)
    var tasksDone = 0
    var focusSeconds = 0.0

    init(data: StoreData, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map { Day(date: $0) }
        guard let first = days.first?.date else { return }

        for task in data.tasks {
            guard let done = task.done, done >= first else { continue }
            let day = calendar.startOfDay(for: done)
            if let index = days.firstIndex(where: { $0.date == day }) { days[index].tasks += 1 }
            hours[calendar.component(.hour, from: done)] += 10
            tasksDone += 1
        }
        for session in data.sessions where session.start >= first {
            let day = calendar.startOfDay(for: session.start)
            if let index = days.firstIndex(where: { $0.date == day }) { days[index].focusMinutes += session.duration / 60 }
            hours[calendar.component(.hour, from: session.start)] += session.duration / 60
            focusSeconds += session.duration
        }
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    var peakHour: Int? {
        guard let max = hours.max(), max > 0 else { return nil }
        return hours.firstIndex(of: max)
    }

    var summary: String {
        guard tasksDone > 0 || focusSeconds > 0 else { return "Finish a task or a focus session to see your week." }
        var text = "\(tasksDone) done · \(Self.duration(focusSeconds)) focused"
        if let peakHour {
            let date = Calendar.current.date(bySettingHour: peakHour, minute: 0, second: 0, of: Date()) ?? Date()
            text += " · best around \(date.formatted(.dateTime.hour()))"
        }
        return text
    }
}
