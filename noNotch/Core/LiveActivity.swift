import Foundation
import SwiftUI

enum HUDKind: Equatable {
    case volume(muted: Bool)
    case brightness
}

/// A short-lived event shown in the collapsed notch "wings".
enum LiveActivity: Equatable {
    case hud(HUDKind, value: Double)
    case power(level: Int, charging: Bool, pluggedIn: Bool)
    case lowBattery(level: Int)
    case bluetooth(name: String, symbol: String, connected: Bool)
    case download(name: String, bytes: Int64, finished: Bool, url: URL?)
    case event(title: String, minutes: Int)
    case timerFinished(String)
    case eyeBreak(until: Date)
    case notification(NotificationMirror.Item)

    /// Higher wins. HUD always replaces whatever is showing.
    var priority: Int {
        switch self {
        case .hud: 100
        case .notification: 85
        case .lowBattery: 80
        case .eyeBreak: 75
        case .event: 70
        case .timerFinished: 65
        case .power: 60
        case .bluetooth: 50
        case .download: 40
        }
    }

    var duration: Duration {
        switch self {
        case .hud: .milliseconds(1500)
        case .download(_, _, let finished, _): finished ? .seconds(4) : .seconds(30)
        case .event: .seconds(6)
        case .notification: .seconds(5)
        case .eyeBreak(let until): .seconds(max(until.timeIntervalSinceNow, 1))
        default: .seconds(3)
        }
    }

    /// Activities of the same kind update in place instead of queueing.
    func isSameKind(as other: LiveActivity) -> Bool {
        switch (self, other) {
        case (.hud, .hud), (.power, .power), (.lowBattery, .lowBattery),
             (.bluetooth, .bluetooth), (.download, .download), (.event, .event),
             (.timerFinished, .timerFinished), (.eyeBreak, .eyeBreak), (.notification, .notification):
            true
        default:
            false
        }
    }
}

/// Priority queue for live activities with per-item display durations.
@MainActor
@Observable
final class ActivityCenter {
    private(set) var current: LiveActivity?
    @ObservationIgnored private var queue: [LiveActivity] = []
    @ObservationIgnored private var expiry: Task<Void, Never>?

    func post(_ activity: LiveActivity) {
        if let current, current.isSameKind(as: activity) || activity.priority > current.priority {
            if !current.isSameKind(as: activity) { queue.insert(current, at: 0) }
            show(activity)
        } else if current == nil {
            show(activity)
        } else {
            queue.removeAll { $0.isSameKind(as: activity) }
            queue.append(activity)
            queue.sort { $0.priority > $1.priority }
        }
    }

    func dismiss() {
        expiry?.cancel()
        let next = queue.isEmpty ? nil : queue.removeFirst()
        withAnimation(NotchViewModel.spring) { current = next }
        if let next { scheduleExpiry(for: next) }
    }

    private func show(_ activity: LiveActivity) {
        withAnimation(NotchViewModel.spring) { current = activity }
        scheduleExpiry(for: activity)
    }

    private func scheduleExpiry(for activity: LiveActivity) {
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: activity.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
