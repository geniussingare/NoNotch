import AppKit
import Observation

/// Focus sessions: a countdown (with an automatic short break) or an open-ended stopwatch,
/// optionally tied to a task. Sessions are logged for Insights; the timer pauses while the Mac sleeps.
@MainActor
@Observable
final class FocusTimer {
    enum Mode: String, CaseIterable {
        case countdown
        case stopwatch

        var title: String { self == .countdown ? "Timer" : "Stopwatch" }
    }

    enum Phase: Equatable {
        case idle
        case focus
        case shortBreak

        var title: String {
            switch self {
            case .idle: "Ready"
            case .focus: "Focus"
            case .shortBreak: "Break"
            }
        }
    }

    var mode: Mode = .countdown
    private(set) var phase: Phase = .idle
    /// Countdown end while running.
    private(set) var endDate: Date?
    /// Stopwatch run start while running.
    private(set) var runStart: Date?
    /// Countdown remaining while paused.
    private(set) var pausedRemaining: TimeInterval?
    /// Stopwatch time banked before the current run.
    private(set) var banked: TimeInterval = 0
    /// Length of the current countdown phase, including any +5 min.
    private(set) var length: TimeInterval = 0
    private(set) var taskID: UUID?
    private(set) var completedSessions = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var onActivity: (LiveActivity) -> Void = { _ in }
    @ObservationIgnored private var store: TaskStore?
    @ObservationIgnored private var phaseStart: Date?
    @ObservationIgnored private var pausedBySleep = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var focusLength: TimeInterval { UserDefaults.standard.pomodoroMinutes * 60 }
    var breakLength: TimeInterval { 5 * 60 }

    var isRunning: Bool { endDate != nil || runStart != nil }
    var isActive: Bool { phase != .idle }
    var isPaused: Bool { isActive && !isRunning }

    var totalLength: TimeInterval { length > 0 ? length : focusLength }

    // MARK: - Reading

    /// Countdown: time left. Stopwatch: time elapsed.
    func display(at date: Date) -> TimeInterval {
        mode == .stopwatch && phase == .focus ? elapsed(at: date) : remaining(at: date)
    }

    func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return phase == .idle ? focusLength : 0 }
        return max(endDate.timeIntervalSince(date), 0)
    }

    /// Focused time in the current phase.
    func elapsed(at date: Date) -> TimeInterval {
        if mode == .stopwatch, phase == .focus {
            return banked + (runStart.map { date.timeIntervalSince($0) } ?? 0)
        }
        return phase == .idle ? 0 : max(totalLength - remaining(at: date), 0)
    }

    /// Ring fill: countdown progress, or a sweeping minute hand for the stopwatch.
    func progress(at date: Date) -> Double {
        guard phase != .idle else { return 0 }
        if mode == .stopwatch, phase == .focus {
            return elapsed(at: date).truncatingRemainder(dividingBy: 60) / 60
        }
        return 1 - remaining(at: date) / totalLength
    }

    // MARK: - Setup

    func configure(store: TaskStore, onActivity: @escaping (LiveActivity) -> Void) {
        self.store = store
        self.onActivity = onActivity
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleep() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            },
        ]
    }

    // MARK: - Controls

    func startOrPause() {
        switch (phase, isRunning) {
        case (.idle, _): start()
        case (_, true): pause()
        case (_, false): resume()
        }
    }

    /// Starts a focus session. `minutes` overrides the default countdown length.
    func start(minutes: Double? = nil, taskID: UUID? = nil, mode: Mode? = nil) {
        logSession()
        if let mode { self.mode = mode }
        self.taskID = taskID ?? self.taskID
        begin(.focus, length: minutes.map { $0 * 60 } ?? focusLength)
    }

    func focus(on taskID: UUID?) {
        self.taskID = taskID
        snapshot()
    }

    func pause() {
        guard isRunning else { return }
        if mode == .stopwatch, phase == .focus, let runStart {
            banked += Date().timeIntervalSince(runStart)
            self.runStart = nil
        } else {
            pausedRemaining = remaining(at: Date())
            endDate = nil
        }
        task?.cancel()
        snapshot()
    }

    func resume() {
        guard isPaused else { return }
        if mode == .stopwatch, phase == .focus {
            runStart = Date()
        } else if let pausedRemaining {
            self.pausedRemaining = nil
            schedule(end: Date().addingTimeInterval(pausedRemaining))
        }
        snapshot()
    }

    func addFiveMinutes() {
        guard isActive, !(mode == .stopwatch && phase == .focus) else { return }
        length += 300
        if let endDate {
            schedule(end: endDate.addingTimeInterval(300))
        } else if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + 300
        }
        snapshot()
    }

    /// Stops and logs whatever was focused so far.
    func reset() {
        logSession()
        task?.cancel()
        phase = .idle
        endDate = nil
        runStart = nil
        pausedRemaining = nil
        banked = 0
        length = 0
        snapshot()
    }

    func skip() {
        finishPhase(announce: false)
    }

    // MARK: - Internals

    private func begin(_ phase: Phase, length: TimeInterval) {
        self.phase = phase
        self.length = length
        pausedRemaining = nil
        banked = 0
        phaseStart = Date()
        task?.cancel()
        if mode == .stopwatch, phase == .focus {
            endDate = nil
            runStart = Date()
            snapshot()
        } else {
            runStart = nil
            schedule(end: Date().addingTimeInterval(length))
        }
    }

    private func schedule(end: Date) {
        endDate = end
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.finishPhase(announce: true)
        }
        snapshot()
    }

    private func finishPhase(announce: Bool) {
        let finished = phase
        logSession()
        if finished == .focus { completedSessions += 1 }
        if announce {
            NSSound(named: "Glass")?.play()
            onActivity(.timerFinished(finished == .focus ? "Focus done — take a break" : "Break over — back to it"))
        }
        if finished == .focus, mode == .countdown, UserDefaults.standard.autoBreak {
            begin(.shortBreak, length: breakLength)
        } else if finished == .shortBreak {
            begin(.focus, length: focusLength)
        } else {
            reset()
        }
    }

    /// Records the focused part of the current phase (a minute or more) for Insights.
    private func logSession() {
        guard phase == .focus, let start = phaseStart, let store else { return }
        let focused = elapsed(at: Date())
        phaseStart = nil
        guard focused >= 60 else { return }
        let session = FocusSession(start: start, duration: focused, taskID: taskID)
        store.mutate { $0.sessions.append(session) }
    }

    private func sleep() {
        guard isRunning else { return }
        pausedBySleep = true
        pause()
    }

    private func wake() {
        guard pausedBySleep else { return }
        pausedBySleep = false
        resume()
    }

    /// Mirrors state to disk for the MCP helper. Only on changes, never per second.
    private func snapshot() {
        guard let store else { return }
        let now = Date()
        let value: TimerSnapshot? = phase == .idle ? nil : TimerSnapshot(
            mode: mode == .countdown || phase == .shortBreak ? .countdown : .stopwatch,
            phase: phase.title.lowercased(),
            running: isRunning,
            seconds: display(at: now),
            taskID: taskID,
            updated: now
        )
        store.mutate { $0.timer = value }
    }
}
