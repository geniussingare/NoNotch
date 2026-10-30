import AppKit
import Observation

@MainActor
@Observable
final class PomodoroTimer {
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

    private(set) var phase: Phase = .idle
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var completedSessions = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var onActivity: (LiveActivity) -> Void = { _ in }

    var focusLength: TimeInterval { UserDefaults.standard.pomodoroMinutes * 60 }
    var breakLength: TimeInterval { 5 * 60 }

    var isRunning: Bool { endDate != nil }
    var isActive: Bool { phase != .idle }

    var totalLength: TimeInterval { phase == .shortBreak ? breakLength : focusLength }

    func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return focusLength }
        return max(endDate.timeIntervalSince(date), 0)
    }

    func progress(at date: Date) -> Double {
        guard phase != .idle else { return 0 }
        return 1 - remaining(at: date) / totalLength
    }

    func configure(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
    }

    func startOrPause() {
        switch (phase, isRunning) {
        case (.idle, _): begin(.focus, length: focusLength)
        case (_, true): pause()
        case (_, false): resume()
        }
    }

    func reset() {
        task?.cancel()
        phase = .idle
        endDate = nil
        pausedRemaining = nil
    }

    func skip() {
        finishPhase(announce: false)
    }

    private func begin(_ phase: Phase, length: TimeInterval) {
        self.phase = phase
        pausedRemaining = nil
        schedule(end: Date().addingTimeInterval(length))
    }

    private func pause() {
        pausedRemaining = remaining(at: Date())
        endDate = nil
        task?.cancel()
    }

    private func resume() {
        guard let pausedRemaining else { return }
        self.pausedRemaining = nil
        schedule(end: Date().addingTimeInterval(pausedRemaining))
    }

    private func schedule(end: Date) {
        endDate = end
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.finishPhase(announce: true)
        }
    }

    private func finishPhase(announce: Bool) {
        let finished = phase
        if finished == .focus { completedSessions += 1 }
        if announce {
            NSSound(named: "Glass")?.play()
            onActivity(.timerFinished(finished == .focus ? "Focus done — take a break" : "Break over — back to it"))
        }
        if finished == .focus {
            begin(.shortBreak, length: breakLength)
        } else {
            begin(.focus, length: focusLength)
        }
    }
}
