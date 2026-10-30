import AppKit
import ServiceManagement
import SwiftUI

/// One short page. Everything else has sensible defaults.
struct SettingsView: View {
    let onPermissions: () -> Void

    @AppStorage(SettingsKey.theme) private var theme = SettingsDefaults.theme
    @AppStorage(SettingsKey.panelScale) private var panelScale = SettingsDefaults.panelScale
    @AppStorage(SettingsKey.featureHUD) private var hud = SettingsDefaults.feature
    @AppStorage(SettingsKey.featureClipboard) private var clipboard = SettingsDefaults.feature
    @AppStorage(SettingsKey.featureCalendar) private var calendar = SettingsDefaults.feature
    @AppStorage(SettingsKey.featureDownloads) private var downloads = SettingsDefaults.feature
    @AppStorage(SettingsKey.featureEyeBreak) private var eyeBreak = SettingsDefaults.feature
    @AppStorage(SettingsKey.featureNotifications) private var notifications = SettingsDefaults.feature
    @AppStorage(SettingsKey.hideSystemBanners) private var hideBanners = SettingsDefaults.hideSystemBanners
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $theme) {
                    ForEach(NotchTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Size", selection: $panelScale) {
                    Text("Small").tag(0.75)
                    Text("Compact").tag(0.85)
                    Text("Regular").tag(1.0)
                    Text("Large").tag(1.15)
                    if ![0.75, 0.85, 1.0, 1.15].contains(panelScale) {
                        Text("Custom").tag(panelScale)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Fine-tune") {
                    Slider(value: $panelScale, in: 0.7...1.2, step: 0.05) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }
                }
            }

            Section {
                Toggle("Notifications in notch", isOn: $notifications)
                if notifications {
                    Toggle("Hide macOS banners", isOn: $hideBanners)
                }
                Toggle("Volume & brightness in notch", isOn: $hud)
                Toggle("Clipboard history", isOn: $clipboard)
                Toggle("Meetings", isOn: $calendar)
                Toggle("Downloads", isOn: $downloads)
                Toggle("Eye-break reminders (20-20-20)", isOn: $eyeBreak)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent("Open notch", value: "⌃⌥Space")
                Button("Permissions…", action: onPermissions)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hosts both the onboarding and settings windows.
@MainActor
final class SettingsWindowController {
    private let services: Services
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(services: Services) {
        self.services = services
    }

    func show() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "noNotch",
                root: SettingsView(onPermissions: { [weak self] in self?.showOnboarding() })
            )
        }
        present(settingsWindow)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = makeWindow(
                title: "",
                root: OnboardingView(permissions: .shared) { [weak self] in
                    self?.onboardingWindow?.close()
                    self?.services.apply()
                }
            )
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            onboardingWindow = window
        }
        present(onboardingWindow)
    }

    private func makeWindow<Root: View>(title: String, root: Root) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
