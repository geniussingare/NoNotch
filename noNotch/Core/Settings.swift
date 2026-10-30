import Foundation

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

enum SettingsKey {
    static let theme = "theme"
    static let hoverDelay = "hoverDelay"
    static let hapticsEnabled = "hapticsEnabled"
    static let display = "display"
    static let focusShortcut = "focusShortcut"
    static let pomodoroMinutes = "pomodoroMinutes"
    static let panelScale = "panelScale"

    static let featureHUD = "feature.hud"
    static let featureBattery = "feature.battery"
    static let featureBluetooth = "feature.bluetooth"
    static let featureDownloads = "feature.downloads"
    static let featureCalendar = "feature.calendar"
    static let featureClipboard = "feature.clipboard"
    static let featureEyeBreak = "feature.eyeBreak"
    static let featureNotifications = "feature.notifications"
    static let hideSystemBanners = "hideSystemBanners"
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
    var pomodoroMinutes: Double { value(SettingsKey.pomodoroMinutes, default: SettingsDefaults.pomodoroMinutes) }

    var display: DisplayChoice {
        string(forKey: SettingsKey.display).flatMap(DisplayChoice.init(rawValue:)) ?? SettingsDefaults.display
    }

    func isEnabled(_ featureKey: String, default fallback: Bool = SettingsDefaults.feature) -> Bool {
        value(featureKey, default: fallback)
    }
}
