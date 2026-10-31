import AppKit
import Observation

/// Observable view of `store.json`. Every change is applied to the on-disk copy under a lock,
/// so edits made by the MCP helper and the app merge instead of clobbering each other.
@MainActor
@Observable
final class TaskStore {
    private(set) var data: StoreData

    @ObservationIgnored let file: StoreFile
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var dayObserver: NSObjectProtocol?
    @ObservationIgnored private var pending: [(inout StoreData) -> Void] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var dueTask: Task<Void, Never>?
    @ObservationIgnored private var onDue: (TaskItem) -> Void = { _ in }
    /// Called after any saved or reloaded change (Reminders sync listens).
    @ObservationIgnored var onChange: () -> Void = {}
    /// Called when the user adds a task (on-device suggestions listen).
    @ObservationIgnored var onAdded: (TaskItem, ParsedTask) -> Void = { _, _ in }

    init(file: StoreFile = .standard) {
        self.file = file
        data = file.load()
    }

    /// Starts watching the file, rolling over at midnight and firing reminders.
    func start(onDue: @escaping (TaskItem) -> Void) {
        self.onDue = onDue
        mutate { $0.rollOver() }
        watch()
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mutate { $0.rollOver() } }
        }
        scheduleDue()
    }

    // MARK: - Reading

    var today: [TaskItem] { data.todayTasks() }
    var completed: [TaskItem] { data.completedTasks() }
    var upcoming: [TaskItem] { data.upcomingTasks() }
    func task(_ id: UUID) -> TaskItem? { data.task(id) }

    func tasks(on day: Date, calendar: Calendar = .current) -> [TaskItem] {
        let start = calendar.startOfDay(for: day)
        if start == calendar.startOfDay(for: Date()) { return today }
        return data.tasks.filter { !$0.isDone && $0.day == start }.sorted(by: StoreData.displayOrder)
    }

    // MARK: - Writing

    /// Applies `change` locally right away and to disk (immediately, or after a short pause while typing).
    func mutate(debounced: Bool = false, _ change: @escaping (inout StoreData) -> Void) {
        var local = data
        change(&local)
        if local != data { data = local }
        pending.append(change)
        flushTask?.cancel()
        if debounced {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        } else {
            flush()
        }
    }

    func flush() {
        guard !pending.isEmpty else { return }
        let changes = pending
        pending.removeAll()
        let (saved, _) = file.update { disk in changes.forEach { $0(&disk) } }
        if saved != data { data = saved }
        scheduleDue()
        onChange()
    }

    @discardableResult
    func add(_ text: String, defaultDay: Date? = nil) -> UUID? {
        let parsed = TaskParser.parse(text)
        guard !parsed.title.isEmpty else { return nil }
        // Build the task once so the local copy and the saved copy share its id.
        var scratch = StoreData()
        let task = scratch.add(parsed, defaultDay: defaultDay)
        mutate { $0.insert(task) }
        onAdded(task, parsed)
        return task.id
    }

    func update(_ id: UUID, debounced: Bool = false, _ change: @escaping (inout TaskItem) -> Void) {
        mutate(debounced: debounced) { $0.update(id, change) }
    }

    func toggle(_ id: UUID) {
        guard let task = task(id) else { return }
        mutate { $0.setDone(id, !task.isDone) }
    }

    func delete(_ id: UUID) { mutate { $0.delete(id) } }
    func move(_ id: UUID, before target: UUID) { mutate { $0.move(id, before: target) } }

    func snooze(_ id: UUID, minutes: Int = 5) {
        update(id) { $0.due = Date().addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    // MARK: - File watching

    /// Watches the folder: atomic saves replace the file, which a file descriptor wouldn't follow.
    private func watch() {
        try? FileManager.default.createDirectory(at: file.directory, withIntermediateDirectories: true)
        let fd = open(file.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadFromDisk() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func reloadFromDisk() {
        guard pending.isEmpty else { return }
        let disk = file.load()
        guard disk != data else { return }
        data = disk
        scheduleDue()
        onChange()
    }

    // MARK: - Reminders

    /// One sleeping task aimed at the nearest reminder; nothing runs in between.
    private func scheduleDue() {
        dueTask?.cancel()
        let now = Date()
        let pendingDue = data.tasks.filter { !$0.isDone && $0.due != nil && $0.alertedDue != $0.due }
        // Fire anything already due (missed while asleep or quit), but not stale ones from long ago.
        let fireable = pendingDue.filter { $0.due! <= now }
        if !fireable.isEmpty {
            mutate { data in
                for task in fireable { data.update(task.id) { $0.alertedDue = $0.due } }
            }
            fireable.filter { now.timeIntervalSince($0.due!) <= 12 * 3600 }
                .sorted { $0.due! < $1.due! }
                .forEach(onDue)
            return // mutate → flush already rescheduled the next one
        }
        guard let next = pendingDue.compactMap(\.due).min() else { return }
        dueTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0.5)))
            guard !Task.isCancelled else { return }
            self?.scheduleDue()
        }
    }
}
