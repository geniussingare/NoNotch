import Foundation
import CoreGraphics

enum NotchTheme: String, CaseIterable, Identifiable {
    case black
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Pure Black"
        case .glass: "Glass"
        }
    }
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case notched
    case main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notched: "Built-in (notch)"
        case .main: "Main display"
        }
    }
}

enum FocusClockStyle: String, CaseIterable, Identifiable {
    case ring
    case digital
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring: "Ring"
        case .digital: "Digital"
        case .minimal: "Minimal"
        }
    }
}

/// Cards on the Home page, in order, each shown or hidden and narrow or wide.
struct HomeCard: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case clock, agenda, focus, tasks

        var title: String {
            switch self {
            case .clock: "Clock & Weather"
            case .agenda: "Agenda"
            case .focus: "Focus"
            case .tasks: "Today's Tasks"
            }
        }

        var symbol: String {
            switch self {
            case .clock: "clock"
            case .agenda: "calendar"
            case .focus: "timer"
            case .tasks: "checklist"
            }
        }
    }

    var kind: Kind
    var visible = true
    var wide = false

    var id: Kind { kind }

    var width: CGFloat {
        switch kind {
        case .clock: wide ? 132 : 96
        case .agenda: wide ? 190 : 150
        case .focus: wide ? 150 : 104
        case .tasks: wide ? 210 : 160
        }
    }

    static let defaults: [HomeCard] = [
        HomeCard(kind: .clock),
        HomeCard(kind: .agenda, wide: true),
        HomeCard(kind: .focus),
        HomeCard(kind: .tasks, visible: false),
    ]

    /// Saved layout, with any card kinds added in later versions appended.
    static func load(_ defaults: UserDefaults = .standard) -> [HomeCard] {
        var cards = defaults.data(forKey: SettingsKey.homeCards)
            .flatMap { try? JSONDecoder().decode([HomeCard].self, from: $0) } ?? Self.defaults
        for card in Self.defaults where !cards.contains(where: { $0.kind == card.kind }) { cards.append(card) }
        return cards
    }

    static func save(_ cards: [HomeCard], _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(cards), forKey: SettingsKey.homeCards)
    }

    /// Home panel width: visible cards, 29pt dividers between them, 40pt padding.
    static func panelWidth(_ cards: [HomeCard]) -> CGFloat {
        let visible = cards.filter(\.visible)
        let content = visible.reduce(0) { $0 + $1.width } + CGFloat(max(visible.count - 1, 0)) * 29 + 40
        return min(max(content, 380), 640)
    }
}

enum SettingsKey {
    static let theme = "theme"
    static let hoverDelay = "hoverDelay"
    static let hapticsEnabled = "hapticsEnabled"
    static let display = "display"
    static let focusShortcut = "focusShortcut"
    static let pomodoroMinutes = "pomodoroMinutes"
    static let panelScale = "panelScale"
    static let homeCards = "homeCards"
    static let focusClockStyle = "focusClockStyle"
    static let autoBreak = "autoBreak"

    static let featureHUD = "feature.hud"
    static let featureBattery = "feature.battery"
    static let featureBluetooth = "feature.bluetooth"
    static let featureDownloads = "feature.downloads"
    static let featureCalendar = "feature.calendar"
    static let featureClipboard = "feature.clipboard"
    static let featureEyeBreak = "feature.eyeBreak"
    static let featureNotifications = "feature.notifications"
    static let hideSystemBanners = "hideSystemBanners"
    static let featureRemindersSync = "feature.remindersSync"
    static let featureSuggestions = "feature.suggestions"
}

enum SettingsDefaults {
    static let theme = NotchTheme.glass
    static let hoverDelay = 0.12
    static let hapticsEnabled = true
    static let display = DisplayChoice.notched
    static let focusShortcut = "Toggle Do Not Disturb"
    static let pomodoroMinutes = 25.0
    /// Compact by default; Settings → Size offers 70–120%.
    static let panelScale = 0.85
    static let feature = true
    static let focusClockStyle = FocusClockStyle.ring
    static let autoBreak = true
    /// Notifications show in the notch instead of the macOS corner by default.
    static let hideSystemBanners = true
}

extension UserDefaults {
    private func value<T>(_ key: String, default fallback: T) -> T {
        object(forKey: key) as? T ?? fallback
    }

    var hoverDelay: Double { value(SettingsKey.hoverDelay, default: SettingsDefaults.hoverDelay) }
    var hapticsEnabled: Bool { value(SettingsKey.hapticsEnabled, default: SettingsDefaults.hapticsEnabled) }
    var panelScale: Double { value(SettingsKey.panelScale, default: SettingsDefaults.panelScale) }
    var autoBreak: Bool { value(SettingsKey.autoBreak, default: SettingsDefaults.autoBreak) }
    var pomodoroMinutes: Double { value(SettingsKey.pomodoroMinutes, default: SettingsDefaults.pomodoroMinutes) }

    var display: DisplayChoice {
        string(forKey: SettingsKey.display).flatMap(DisplayChoice.init(rawValue:)) ?? SettingsDefaults.display
    }

    func isEnabled(_ featureKey: String, default fallback: Bool = SettingsDefaults.feature) -> Bool {
        value(featureKey, default: fallback)
    }
}
