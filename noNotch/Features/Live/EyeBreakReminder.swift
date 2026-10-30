import CoreGraphics
import Foundation

/// 20-20-20 rule: every 20 minutes of active use, look 20 feet away for 20 seconds.
/// Idle time (no input for 5+ minutes) resets the clock.
@MainActor
final class EyeBreakReminder {
    private static let interval: TimeInterval = 20 * 60
    private static let idleReset: TimeInterval = 5 * 60

    private let onActivity: (LiveActivity) -> Void
    private var timer: Timer?
    private var activeSince = Date()

    init(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
    }

    func start() {
        guard timer == nil else { return }
        activeSince = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 10
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle > Self.idleReset {
            activeSince = Date()
            return
        }
        guard Date().timeIntervalSince(activeSince) >= Self.interval else { return }
        activeSince = Date()
        onActivity(.eyeBreak(until: Date().addingTimeInterval(20)))
    }
}
