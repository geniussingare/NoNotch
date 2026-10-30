import AppKit
import Observation

/// Owns every feature service and starts only the ones enabled in Settings.
@MainActor
@Observable
final class Services {
    let activities = ActivityCenter()
    let media = NowPlayingService()
    let battery = BatteryMonitor()
    let controls = SystemControls()
    let calendar = CalendarService()
    let shelf = FileShelf()
    let clipboard = ClipboardHistory()
    let pomodoro = PomodoroTimer()
    let weather = WeatherService()
    let notes = NotesStore()
    let notifications = NotificationMirror()

    @ObservationIgnored private(set) lazy var keys = MediaKeyInterceptor { [weak self] in self?.post($0) }
    @ObservationIgnored private lazy var bluetooth = BluetoothMonitor { [weak self] in self?.post($0) }
    @ObservationIgnored private lazy var eyeBreak = EyeBreakReminder { [weak self] in self?.post($0) }
    @ObservationIgnored private lazy var downloads = DownloadsWatcher { [weak self] in self?.post($0) }
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var trustObserver: NSObjectProtocol?

    private(set) var hudActive = false

    func start() {
        media.start()
        weather.start()
        pomodoro.configure { [weak self] in self?.post($0) }
        apply()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        // macOS posts this when the Accessibility list changes; trust updates a moment later.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self?.apply()
            }
        }
    }

    func stop() {
        media.stop()
        keys.stop()
        downloads.stop()
        clipboard.stop()
        eyeBreak.stop()
        notifications.stop()
    }

    /// Starts or stops services to match the feature toggles.
    func apply() {
        let defaults = UserDefaults.standard
        if defaults.isEnabled(SettingsKey.featureBattery), !batteryStarted {
            batteryStarted = true
            battery.start { [weak self] in self?.post($0) }
        }
        if defaults.isEnabled(SettingsKey.featureBluetooth), !bluetoothStarted {
            bluetoothStarted = true
            bluetooth.start()
        }
        // Safe to call repeatedly: picks up access granted after launch.
        if defaults.isEnabled(SettingsKey.featureCalendar) {
            calendar.start { [weak self] in self?.post($0) }
        }
        weather.refresh()
        defaults.isEnabled(SettingsKey.featureDownloads) ? downloads.start() : downloads.stop()
        defaults.isEnabled(SettingsKey.featureClipboard) ? clipboard.start() : clipboard.stop()
        defaults.isEnabled(SettingsKey.featureEyeBreak) ? eyeBreak.start() : eyeBreak.stop()
        if defaults.isEnabled(SettingsKey.featureNotifications) {
            notifications.start { [weak self] in self?.post(.notification($0)) }
        } else {
            notifications.stop()
        }

        if defaults.isEnabled(SettingsKey.featureHUD) {
            if !keys.isRunning { keys.start() }
        } else {
            keys.stop()
        }
        hudActive = keys.isRunning
    }

    @ObservationIgnored private var batteryStarted = false
    @ObservationIgnored private var bluetoothStarted = false

    private func post(_ activity: LiveActivity) {
        activities.post(activity)
    }
}
