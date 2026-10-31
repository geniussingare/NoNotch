import AppKit
import Observation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let services: Services
    private let onToggle: () -> Void
    private let onSettings: () -> Void
    private var minuteTimer: Timer?
    private var shown: (MenuBarIcon.State, Bool, String)?

    init(services: Services, onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.services = services
        self.onToggle = onToggle
        self.onSettings = onSettings
        super.init()

        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        observe()

        let menu = NSMenu()
        menu.addItem(item("About noNotch", #selector(about), key: ""))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(item("Toggle Notch", #selector(toggle), key: ""))
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(item("Report a Bug…", #selector(reportBug), key: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit noNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Live icon

    /// Re-renders whenever the focus timer or the live activity changes; nothing runs in between.
    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        let focus = services.focus
        let now = Date()
        var state = MenuBarIcon.State.idle
        var title = ""
        if focus.isActive {
            state = .focus(progress: focus.progress(at: now), paused: focus.isPaused)
            let seconds = focus.display(at: now)
            title = focus.isPaused ? "Paused" : "\(Int((seconds / 60).rounded(focus.mode == .countdown ? .up : .down)))m"
        }
        var alert = services.notifications.unread > 0
        if case .taskDue = services.activities.current { alert = true }

        // While a timer runs, tick the minutes (and the ring) every 15 s.
        if focus.isRunning, minuteTimer == nil {
            minuteTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            minuteTimer?.tolerance = 3
        } else if !focus.isRunning {
            minuteTimer?.invalidate()
            minuteTimer = nil
        }

        let next = (state, alert, title)
        guard shown.map({ $0.0 != next.0 || $0.1 != next.1 || $0.2 != next.2 }) ?? true else { return }
        shown = next
        statusItem.button?.image = MenuBarIcon.image(state, alert: alert)
        statusItem.button?.title = title.isEmpty ? "" : " " + title
        statusItem.button?.toolTip = title.isEmpty ? "noNotch" : "noNotch · Focus \(title)"
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggle() { onToggle() }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "noNotch™",
            .credits: NSAttributedString(
                string: "A GeniusSoft™ product.\nNow Playing uses mediaremote-adapter (BSD-3-Clause).",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
    @objc private func settings() { onSettings() }
    @objc private func checkForUpdates() { UpdateChecker.shared.checkInteractively() }
    @objc private func reportBug() { UpdateChecker.shared.reportBug() }
}
