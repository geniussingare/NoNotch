import Foundation

// Shared by the app and the `nonotch-mcp` helper: Foundation only.

enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    init?(name: String) {
        switch name.lowercased() {
        case "none", "0": self = .none
        case "low", "l", "3": self = .low
        case "medium", "med", "m", "2": self = .medium
        case "high", "h", "1": self = .high
        default: return nil
        }
    }
}

enum RepeatRule: Codable, Hashable, Sendable {
    case daily
    case weekdays
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    case weekly([Int])
    case monthly

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly(let days) where days.count == 1:
            "Every \(Calendar.current.weekdaySymbols[(days[0] - 1) % 7])"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    /// The first matching day strictly after `date`.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: start)!
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: start)!
        case .weekdays, .weekly:
            let days: Set<Int> = if case .weekly(let list) = self, !list.isEmpty { Set(list) } else { [2, 3, 4, 5, 6] }
            var day = start
            for _ in 0..<8 {
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                if days.contains(calendar.component(.weekday, from: day)) { return day }
            }
            return day
        }
    }
}

/// On-device model's guess for a new task, shown until accepted or dismissed.
struct TaskSuggestion: Codable, Hashable, Sendable {
    var priority: TaskPriority?
    var project: String?

    var isEmpty: Bool { (priority ?? TaskPriority.none) == TaskPriority.none && (project ?? "").isEmpty }
}

struct TaskStep: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var done = false
}

struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var notes = ""
    var steps: [TaskStep] = []
    var priority: TaskPriority = .none
    var project: String?
    /// Planned day (start of day). `nil` means "anytime" and shows under Today.
    var day: Date?
    /// Reminder time; the notch opens when it's reached.
    var due: Date?
    var repeatRule: RepeatRule?
    var done: Date?
    var order: Double = 0
    var created = Date()
    var modified = Date()
    /// Apple Reminders `calendarItemIdentifier` when sync is on.
    var remindersID: String?
    /// The `due` value we last alerted for, so each reminder fires once.
    var alertedDue: Date?
    var suggestion: TaskSuggestion?

    var isDone: Bool { done != nil }

    init(title: String) {
        self.title = title
    }

    init(from decoder: Decoder) throws {
        // Tolerant decoding: files written by older builds or by hand still load.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        steps = try c.decodeIfPresent([TaskStep].self, forKey: .steps) ?? []
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        project = try c.decodeIfPresent(String.self, forKey: .project)
        day = try c.decodeIfPresent(Date.self, forKey: .day)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
        done = try c.decodeIfPresent(Date.self, forKey: .done)
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        remindersID = try c.decodeIfPresent(String.self, forKey: .remindersID)
        alertedDue = try c.decodeIfPresent(Date.self, forKey: .alertedDue)
        suggestion = try c.decodeIfPresent(TaskSuggestion.self, forKey: .suggestion)
    }

    /// Belongs on the Today list at `now` (anytime, overdue or today).
    func isToday(_ now: Date, calendar: Calendar = .current) -> Bool {
        guard let day else { return true }
        return day <= calendar.startOfDay(for: now)
    }
}

struct FocusSession: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var start: Date
    var duration: TimeInterval
    var taskID: UUID?
}

/// The running focus timer, mirrored to disk so the MCP helper can report it.
struct TimerSnapshot: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable { case countdown, stopwatch }
    var mode: Mode
    var phase: String
    var running: Bool
    /// Seconds left (countdown) or elapsed (stopwatch) at `updated`.
    var seconds: TimeInterval
    var taskID: UUID?
    var updated: Date
}

/// Everything noNotch keeps for tasks, focus and the daily notepad.
struct StoreData: Codable, Equatable, Sendable {
    var version = 1
    var tasks: [TaskItem] = []
    var sessions: [FocusSession] = []
    /// Daily notepad, keyed by `yyyy-MM-dd`.
    var dailyNotes: [String: String] = [:]
    var timer: TimerSnapshot?
    /// Reminders of tasks deleted here, to be removed from Apple Reminders on the next sync.
    var removedReminders: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        sessions = try c.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? []
        dailyNotes = try c.decodeIfPresent([String: String].self, forKey: .dailyNotes) ?? [:]
        timer = try c.decodeIfPresent(TimerSnapshot.self, forKey: .timer)
        removedReminders = try c.decodeIfPresent([String].self, forKey: .removedReminders) ?? []
    }

    static func noteKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - Mutations (shared so the app and the MCP helper behave the same)

extension StoreData {
    func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    /// Today's open tasks in display order.
    func todayTasks(_ now: Date = Date()) -> [TaskItem] {
        tasks.filter { !$0.isDone && $0.isToday(now) }.sorted(by: Self.displayOrder)
    }

    func completedTasks() -> [TaskItem] {
        tasks.filter(\.isDone).sorted { ($0.done ?? .distantPast) > ($1.done ?? .distantPast) }
    }

    /// Open tasks planned after today, by day.
    func upcomingTasks(_ now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        return tasks.filter { !$0.isDone && ($0.day.map { $0 > today } ?? false) }
            .sorted { ($0.day!, $0.order) < ($1.day!, $1.order) }
    }

    static func displayOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        a.order != b.order ? a.order < b.order : a.created < b.created
    }

    @discardableResult
    mutating func add(_ parsed: ParsedTask, defaultDay: Date? = nil, now: Date = Date()) -> TaskItem {
        var task = TaskItem(title: parsed.title)
        task.priority = parsed.priority ?? .none
        task.project = parsed.project
        task.day = parsed.day ?? defaultDay
        task.due = parsed.due
        task.repeatRule = parsed.repeatRule
        task.created = now
        task.modified = now
        task.order = (tasks.map(\.order).max() ?? 0) + 1
        tasks.append(task)
        return task
    }

    /// Appends a task built elsewhere, placing it last.
    mutating func insert(_ task: TaskItem) {
        guard self.task(task.id) == nil else { return }
        var task = task
        task.order = (tasks.map(\.order).max() ?? 0) + 1
        tasks.append(task)
    }

    mutating func update(_ id: UUID, now: Date = Date(), _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = tasks[index]
        change(&task)
        guard task != tasks[index] else { return }
        task.modified = now
        tasks[index] = task
    }

    /// Completes (or reopens) a task. Completing a repeating task schedules its next occurrence.
    mutating func setDone(_ id: UUID, _ done: Bool, now: Date = Date(), calendar: Calendar = .current) {
        guard let original = task(id), original.isDone != done else { return }
        update(id, now: now) { $0.done = done ? now : nil }
        guard done, let rule = original.repeatRule else { return }

        let base = original.day ?? calendar.startOfDay(for: now)
        let nextDay = rule.next(after: max(base, calendar.startOfDay(for: now)), calendar: calendar)
        var next = original
        next.id = UUID()
        next.done = nil
        next.remindersID = nil
        next.alertedDue = nil
        next.steps = original.steps.map { var step = $0; step.done = false; return step }
        next.day = nextDay
        if let due = original.due {
            let time = calendar.dateComponents([.hour, .minute], from: due)
            next.due = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: nextDay)
        }
        next.created = now
        next.modified = now
        tasks.append(next)
        // The finished copy no longer repeats; the new one carries the rule.
        update(id, now: now) { $0.repeatRule = nil }
    }

    mutating func delete(_ id: UUID) {
        if let remindersID = task(id)?.remindersID { removedReminders.append(remindersID) }
        tasks.removeAll { $0.id == id }
    }

    /// Moves `id` just before `target` in display order.
    mutating func move(_ id: UUID, before target: UUID) {
        guard id != target else { return }
        let ordered = tasks.sorted(by: Self.displayOrder).map(\.id).filter { $0 != id }
        guard let targetIndex = ordered.firstIndex(of: target) else { return }
        var result = ordered
        result.insert(id, at: targetIndex)
        for (position, taskID) in result.enumerated() {
            if let index = tasks.firstIndex(where: { $0.id == taskID }), tasks[index].order != Double(position) {
                tasks[index].order = Double(position)
            }
        }
    }

    /// Unfinished work from earlier days moves to today. Returns true if anything changed.
    @discardableResult
    mutating func rollOver(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        var changed = false
        for index in tasks.indices where !tasks[index].isDone {
            if let day = tasks[index].day, day < today {
                tasks[index].day = today
                tasks[index].modified = now
                changed = true
            }
        }
        return changed
    }
}
