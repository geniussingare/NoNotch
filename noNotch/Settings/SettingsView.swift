import AppKit
import ServiceManagement
import SwiftUI

/// One short page. Everything else has sensible defaults.
struct SettingsView: View {
    let services: Services
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
    @AppStorage(SettingsKey.pomodoroMinutes) private var focusMinutes = SettingsDefaults.pomodoroMinutes
    @AppStorage(SettingsKey.focusClockStyle) private var clockStyle = SettingsDefaults.focusClockStyle
    @AppStorage(SettingsKey.autoBreak) private var autoBreak = SettingsDefaults.autoBreak
    @AppStorage(SettingsKey.featureRemindersSync) private var remindersSync = false
    @AppStorage(SettingsKey.featureSuggestions) private var suggestions = SettingsDefaults.feature
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

            Section("Tasks") {
                Toggle(isOn: $remindersSync) {
                    Text("Sync with Apple Reminders")
                    Text("Two-way, with a “noNotch” list. Reaches iPhone and Apple Watch.")
                }
                if remindersSync {
                    RemindersStatusRow(sync: services.reminders)
                }
                if services.suggester.isAvailable {
                    Toggle(isOn: $suggestions) {
                        Text("Suggest priority and project")
                        Text("Apple Intelligence, on this Mac.")
                    }
                }
            }

            Section("AI agents") {
                AgentsSection(connector: services.agents)
            }

            Section("Home") {
                HomeLayoutEditor()
            }

            Section("Focus") {
                Picker("Length", selection: $focusMinutes) {
                    ForEach([15.0, 25, 45, 60, 90], id: \.self) { Text("\(Int($0)) min").tag($0) }
                }
                Picker("Clock", selection: $clockStyle) {
                    ForEach(FocusClockStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Short break after each session", isOn: $autoBreak)
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

            Section {
                LabeledContent("Version", value: UpdateChecker.shared.current)
                HStack {
                    Button("Check for Updates…") { UpdateChecker.shared.checkInteractively() }
                    Spacer()
                    Button {
                        UpdateChecker.shared.reportBug()
                    } label: {
                        Label("Report a Bug", systemImage: "ladybug.fill")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Connect Claude Code, the Claude app and Cursor to noNotch's MCP server.
private struct AgentsSection: View {
    let connector: AgentConnector
    @State private var copied: String?

    var body: some View {
        ForEach(AgentConnector.Client.allCases) { client in
            HStack(spacing: 10) {
                Image(systemName: client.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.orange.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(client.title)
                    Text(connector.messages[client] ?? statusText(client))
                        .font(.caption)
                        .foregroundStyle(connector.isConnected(client) ? .green : .secondary)
                }
                Spacer()
                if connector.busy.contains(client) {
                    ProgressView().controlSize(.small)
                } else {
                    if connector.isConnected(client), client.bundleID != nil, connector.isRunning(client) {
                        Button("Restart") { connector.restart(client) }
                    }
                    if connector.isConnected(client) {
                        Button("Disconnect") { connector.disconnect(client) }
                    } else {
                        Button(connector.isStale(client) ? "Reconnect" : "Connect") { connector.connect(client) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!connector.isInstalled(client))
                    }
                }
            }
        }

        DisclosureGroup("Try asking") {
            ForEach(AgentConnector.suggestions, id: \.self) { prompt in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt, forType: .string)
                    withAnimation { copied = prompt }
                } label: {
                    HStack {
                        Text(prompt).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: copied == prompt ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied == prompt ? .green : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
        }
    }

    private func statusText(_ client: AgentConnector.Client) -> String {
        if !connector.isInstalled(client) { return "Not installed" }
        if connector.isStale(client) { return "Set up for another copy of noNotch" }
        return client.detail
    }
}

private struct RemindersStatusRow: View {
    let sync: RemindersSync

    var body: some View {
        switch sync.status {
        case .needsAccess, .off:
            HStack {
                Label("Reminders access needed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Allow") { Task { await sync.requestAccess() } }
                Button("Open Settings", action: sync.openPrivacySettings)
            }
        case .syncing:
            LabeledContent("Status") { ProgressView().controlSize(.small) }
        case .synced(let date):
            LabeledContent("Last synced") { Text(date, format: .relative(presentation: .named)) }
        case .failed(let message):
            LabeledContent("Sync failed") { Text(message).foregroundStyle(.red) }
        }
    }
}

/// Show, hide, resize and reorder the Home cards.
private struct HomeLayoutEditor: View {
    @State private var cards = HomeCard.load()

    var body: some View {
        ForEach(Array(cards.enumerated()), id: \.element.kind) { index, card in
            HStack(spacing: 8) {
                Toggle(isOn: binding(index, \.visible)) {
                    Label(card.kind.title, systemImage: card.kind.symbol)
                }
                .toggleStyle(.checkbox)
                Spacer()
                Picker("", selection: binding(index, \.wide)) {
                    Text("Narrow").tag(false)
                    Text("Wide").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(!card.visible)
                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(index == cards.count - 1)
            }
        }
        Button("Reset Layout") { update { $0 = HomeCard.defaults } }
            .disabled(cards == HomeCard.defaults)
    }

    private func binding(_ index: Int, _ key: WritableKeyPath<HomeCard, Bool>) -> Binding<Bool> {
        Binding(get: { cards[index][keyPath: key] }, set: { value in update { $0[index][keyPath: key] = value } })
    }

    private func move(_ index: Int, by offset: Int) {
        update { $0.swapAt(index, index + offset) }
    }

    private func update(_ change: (inout [HomeCard]) -> Void) {
        change(&cards)
        // Keep at least one card visible.
        if !cards.contains(where: \.visible) { cards[0].visible = true }
        HomeCard.save(cards)
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
                root: SettingsView(services: services, onPermissions: { [weak self] in self?.showOnboarding() })
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
