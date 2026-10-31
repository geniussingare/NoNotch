import AppKit
import EventKit
import Observation

/// Optional two-way sync with a "noNotch" list in Apple Reminders, so tasks reach iPhone and Apple Watch.
///
/// Newest edit wins per task. Each repeat occurrence syncs as a plain reminder (noNotch creates the
/// next one itself), deletions on either side propagate, and nothing runs unless the list changes.
@MainActor
@Observable
final class RemindersSync {
    enum Status: Equatable {
        case off
        case needsAccess
        case syncing
        case synced(Date)
        case failed(String)
    }

    static let listName = "noNotch"

    private(set) var status: Status = .off

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private weak var store: TaskStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var lastFingerprint: Int?
    @ObservationIgnored private var running = false

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func start(store: TaskStore) {
        self.store = store
        guard !running else { return }
        guard isAuthorized else {
            status = .needsAccess
            return
        }
        running = true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(force: true) }
        }
        schedule(force: true)
    }

    func stop() {
        running = false
        pendingSync?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        lastFingerprint = nil
        status = .off
    }

    func requestAccess() async {
        let granted = (try? await eventStore.requestFullAccessToReminders()) ?? false
        if granted, let store {
            start(store: store)
        } else {
            status = .needsAccess
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
    }

    /// The task store changed; sync if the tasks themselves did.
    func storeChanged() {
        guard running else { return }
        schedule(force: false)
    }

    private func schedule(force: Bool) {
        guard let store else { return }
        var hasher = Hasher()
        hasher.combine(store.data.tasks)
        hasher.combine(store.data.removedReminders)
        let fingerprint = hasher.finalize()
        guard force || fingerprint != lastFingerprint else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: - Sync

    private func sync() async {
        guard running, let store else { return }
        status = .syncing
        do {
            let list = try calendar()
            let reminders = await fetch(in: list)
            var byID: [String: EKReminder] = [:]
            for reminder in reminders { byID[reminder.calendarItemIdentifier] = reminder }

            var dirty = false
            let snapshot = store.data
            let recentCutoff = Date().addingTimeInterval(-7 * 86400)

            // Deleted in noNotch → delete in Reminders.
            for id in snapshot.removedReminders {
                if let reminder = byID.removeValue(forKey: id) {
                    try eventStore.remove(reminder, commit: false)
                    dirty = true
                }
            }

            var taskChanges: [(inout StoreData) -> Void] = []
            if !snapshot.removedReminders.isEmpty {
                let handled = snapshot.removedReminders
                taskChanges.append { $0.removedReminders.removeAll { handled.contains($0) } }
            }

            for task in snapshot.tasks {
                if let remindersID = task.remindersID {
                    guard let reminder = byID.removeValue(forKey: remindersID) else {
                        // Deleted on another device.
                        let id = task.id
                        taskChanges.append { $0.tasks.removeAll { $0.id == id } }
                        continue
                    }
                    let theirs = reminder.lastModifiedDate ?? .distantPast
                    if theirs > task.modified.addingTimeInterval(1) {
                        let incoming = Self.fields(of: reminder)
                        let id = task.id
                        taskChanges.append { data in data.update(id, now: theirs) { incoming.apply(to: &$0) } }
                    } else if Self.fields(of: reminder) != Self.fields(of: task) {
                        Self.write(task, to: reminder)
                        try eventStore.save(reminder, commit: false)
                        dirty = true
                    }
                } else if !task.isDone || (task.done ?? .distantPast) > recentCutoff {
                    // New in noNotch → create in Reminders.
                    let reminder = EKReminder(eventStore: eventStore)
                    reminder.calendar = list
                    Self.write(task, to: reminder)
                    try eventStore.save(reminder, commit: false)
                    dirty = true
                    let id = task.id, remindersID = reminder.calendarItemIdentifier
                    taskChanges.append { data in
                        if let index = data.tasks.firstIndex(where: { $0.id == id }) { data.tasks[index].remindersID = remindersID }
                    }
                }
            }

            // New in Reminders → create in noNotch (open ones only).
            for reminder in byID.values where !reminder.isCompleted {
                var task = TaskItem(title: reminder.title ?? "Untitled")
                Self.fields(of: reminder).apply(to: &task)
                task.remindersID = reminder.calendarItemIdentifier
                task.created = reminder.creationDate ?? Date()
                task.modified = reminder.lastModifiedDate ?? Date()
                taskChanges.append { $0.insert(task) }
            }

            if dirty { try eventStore.commit() }
            if !taskChanges.isEmpty {
                store.mutate { data in taskChanges.forEach { $0(&data) } }
            }
            var hasher = Hasher()
            hasher.combine(store.data.tasks)
            hasher.combine(store.data.removedReminders)
            lastFingerprint = hasher.finalize()
            status = .synced(Date())
        } catch {
            eventStore.reset()
            status = .failed(error.localizedDescription)
        }
    }

    private func calendar() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == Self.listName }) {
            return existing
        }
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = Self.listName
        list.cgColor = NSColor.systemOrange.cgColor
        guard let source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw NSError(domain: "noNotch", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Reminders account found"])
        }
        list.source = source
        try eventStore.saveCalendar(list, commit: true)
        return list
    }

    private func fetch(in list: EKCalendar) async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [list])
        let box = await withCheckedContinuation { (continuation: CheckedContinuation<ReminderBox, Never>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: ReminderBox(reminders: reminders ?? []))
            }
        }
        return box.reminders
    }

    // MARK: - Mapping

    /// The fields both sides share, for comparison and copying.
    struct Fields: Equatable {
        var title: String
        var notes: String
        var done: Bool
        var priority: TaskPriority
        var day: Date?
        /// Minute precision; Reminders drops seconds.
        var due: Date?

        func apply(to task: inout TaskItem) {
            task.title = title
            task.notes = notes
            if done != task.isDone { task.done = done ? Date() : nil }
            task.priority = priority
            task.day = day
            if task.due.map(Fields.minute) != due { task.due = due }
        }

        static func minute(_ date: Date) -> Date {
            Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        }
    }

    static func fields(of task: TaskItem) -> Fields {
        Fields(title: task.title, notes: task.notes, done: task.isDone, priority: task.priority, day: task.day, due: task.due.map(Fields.minute))
    }

    static func fields(of reminder: EKReminder) -> Fields {
        let calendar = Calendar.current
        var day: Date?
        var due: Date?
        if let components = reminder.dueDateComponents, let date = calendar.date(from: components) {
            day = calendar.startOfDay(for: date)
            if components.hour != nil { due = Fields.minute(date) }
        }
        return Fields(
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            done: reminder.isCompleted,
            priority: priority(fromEventKit: reminder.priority),
            day: day,
            due: due
        )
    }

    static func write(_ task: TaskItem, to reminder: EKReminder) {
        let calendar = Calendar.current
        reminder.title = task.title
        reminder.notes = task.notes.isEmpty ? nil : task.notes
        reminder.isCompleted = task.isDone
        reminder.priority = eventKitPriority(task.priority)
        if let due = task.due {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.alarms = [EKAlarm(absoluteDate: Fields.minute(due))]
        } else if let day = task.day {
            reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: day)
            reminder.alarms = nil
        } else {
            reminder.dueDateComponents = nil
            reminder.alarms = nil
        }
    }

    /// EventKit: 1–4 high, 5 medium, 6–9 low, 0 none.
    static func priority(fromEventKit value: Int) -> TaskPriority {
        switch value {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
    }

    static func eventKitPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 1
        case .medium: 5
        case .low: 9
        case .none: 0
        }
    }
}

/// EventKit objects aren't Sendable; the fetch callback hands them straight back to the main actor.
private struct ReminderBox: @unchecked Sendable {
    let reminders: [EKReminder]
}
