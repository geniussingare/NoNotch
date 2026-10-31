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
    let focus = FocusTimer()
    let weather = WeatherService()
    let notes = NotesStore()
    let notifications = NotificationMirror()
    let tasks = TaskStore()
    let reminders = RemindersSync()
    let suggester = PrioritySuggester()
    let agents = AgentConnector()

    /// Set by the view model: opens the notch on a reminder.
    @ObservationIgnored var onTaskDue: (TaskItem) -> Void = { _ in }

    @ObservationIgnored private(set) lazy var keys = MediaKeyInterceptor { [weak self] in self?.post($0) }
    @ObservationIgnored private lazy var bluetooth = BluetoothMonitor { [weak self] in self?.post($0) }
    @ObservationIgnored private lazy var eyeBreak = EyeBreakReminder { [weak self] in self?.post($0) }
    @ObservationIgnored private lazy var downloads = DownloadsWatcher { [weak self] in self?.post($0) }
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var trustObserver: NSObjectProtocol?
    @ObservationIgnored private var commandObserver: NSObjectProtocol?

    private(set) var hudActive = false

    func start() {
        media.start()
        weather.start()
        tasks.onChange = { [weak self] in self?.reminders.storeChanged() }
        tasks.onAdded = { [weak self] task, parsed in self?.suggest(for: task, parsed: parsed) }
        tasks.start { [weak self] in self?.onTaskDue($0) }
        focus.configure(store: tasks) { [weak self] in self?.post($0) }
        // A brief hello in the wings on launch.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.post(.welcome)
        }
        apply()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        // Focus commands from the MCP helper (Claude Code, the Claude app, Cursor).
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppCommand.name, object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo as? [String: String] ?? [:]
            MainActor.assumeIsolated { self?.handle(command: info) }
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
        tasks.flush()
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

        if defaults.isEnabled(SettingsKey.featureRemindersSync, default: false) {
            reminders.start(store: tasks)
        } else {
            reminders.stop()
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

    private func handle(command info: [String: String]) {
        guard let action = info[AppCommand.Key.action].flatMap(AppCommand.Action.init(rawValue:)) else { return }
        switch action {
        case .focusStart:
            let mode = info[AppCommand.Key.mode].flatMap(FocusTimer.Mode.init(rawValue:))
            focus.start(
                minutes: info[AppCommand.Key.minutes].flatMap(Double.init),
                taskID: info[AppCommand.Key.taskID].flatMap(UUID.init(uuidString:)),
                mode: mode
            )
        case .focusPause: focus.pause()
        case .focusResume: focus.resume()
        case .focusAddFive: focus.addFiveMinutes()
        case .focusStop: focus.reset()
        }
    }

    /// Offers an on-device priority/project guess when the user typed neither.
    private func suggest(for task: TaskItem, parsed: ParsedTask) {
        guard parsed.priority == nil, parsed.project == nil, suggester.isEnabled else { return }
        let projects = Array(Set(tasks.data.tasks.compactMap(\.project))).sorted()
        Task { [weak self] in
            guard let self, let suggestion = await suggester.suggest(for: task, knownProjects: projects) else { return }
            tasks.update(task.id) { item in
                guard item.priority == .none, item.project == nil else { return }
                item.suggestion = suggestion
            }
        }
    }

    private func post(_ activity: LiveActivity) {
        activities.post(activity)
    }
}
