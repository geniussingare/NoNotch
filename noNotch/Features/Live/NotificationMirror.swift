import AppKit
import ApplicationServices
import Observation
import os

/// Mirrors system notification banners into the notch.
///
/// macOS has no public API for reading other apps' notifications, so this
/// watches Notification Center's own banner windows through Accessibility and
/// reads their text. Optionally it closes the system banner afterwards so only
/// the notch version shows. If Apple changes the banner layout, parsing simply
/// finds nothing and system banners keep working as usual.
@MainActor
@Observable
final class NotificationMirror {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let appName: String
        let title: String
        let body: String
        let date: Date
        let appURL: URL?

        var icon: NSImage {
            appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)!
        }
    }

    private static let centerBundleID = "com.apple.notificationcenterui"
    private static let log = Logger(subsystem: "com.ganeshsingare.noNotch", category: "notifications")
    private static let historyLimit = 30
    /// Texts Notification Center adds that aren't part of the message.
    private static let noise: Set<String> = ["now", "Now", "Notification Center", "Close", "Options", "Show", "Clear All"]

    private(set) var history: [Item] = []
    private(set) var unread = 0

    @ObservationIgnored private var onActivity: (Item) -> Void = { _ in }
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var appElement: AXUIElement?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var recent: [String: Date] = [:]
    @ObservationIgnored private var launchObserver: NSObjectProtocol?
    @ObservationIgnored private var running = false

    func start(onActivity: @escaping (Item) -> Void) {
        self.onActivity = onActivity
        guard !running, AXIsProcessTrusted() else { return }
        running = true
        attach()
        // Notification Center restarts occasionally; follow it.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if id == Self.centerBundleID { self?.attach() }
            }
        }
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        running = false
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
    }

    func markRead() { unread = 0 }

    func clear() {
        history.removeAll()
        unread = 0
    }

    func open(_ item: Item) {
        guard let url = item.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Accessibility observation

    private func attach() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerBundleID).first else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let mirror = Unmanaged<NotificationMirror>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { mirror.scheduleScan() }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created else { return }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        appElement = element
        Self.log.info("Watching Notification Center (pid \(app.processIdentifier))")
    }

    /// Banners build their contents over a few frames; read once they settle.
    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    private func scan() {
        guard let appElement else { return }
        let windows: [AXUIElement] = Self.attribute(appElement, kAXWindowsAttribute) ?? []
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 15 }

        for window in windows {
            for banner in Self.banners(in: window) {
                guard let item = parse(banner) else { continue }
                let signature = item.appName + "|" + item.title + "|" + item.body
                guard recent[signature] == nil else { continue }
                recent[signature] = now

                history.insert(item, at: 0)
                if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
                unread += 1
                Self.log.info("Captured notification from \(item.appName, privacy: .public)")
                onActivity(item)

                if UserDefaults.standard.isEnabled(SettingsKey.hideSystemBanners, default: SettingsDefaults.hideSystemBanners) {
                    Self.close(banner)
                }
            }
        }
    }

    // MARK: - Parsing

    /// Banner groups are tagged with a "Banner"/"Alert" subrole on recent macOS;
    /// older layouts fall back to treating the whole window as one banner.
    private static func banners(in window: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        walk(window, depth: 0) { element in
            let subrole: String = attribute(element, kAXSubroleAttribute) ?? ""
            if subrole.contains("Banner") || subrole.contains("Alert") {
                found.append(element)
                return false
            }
            return true
        }
        return found.isEmpty ? [window] : found
    }

    private func parse(_ banner: AXUIElement) -> Item? {
        var texts: [String] = []
        Self.walk(banner, depth: 0) { element in
            let role: String = Self.attribute(element, kAXRoleAttribute) ?? ""
            if role == kAXStaticTextRole, let value: String = Self.attribute(element, kAXValueAttribute) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !Self.noise.contains(trimmed), !texts.contains(trimmed), !Self.isTimestamp(trimmed) {
                    texts.append(trimmed)
                }
            }
            return true
        }
        guard let title = texts.first else { return nil }

        // The group's description usually starts with the app name ("Messages, …").
        let description: String = Self.attribute(banner, kAXDescriptionAttribute) ?? ""
        let candidate = description.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let appURL = Self.appURL(named: candidate)
        let appName = appURL != nil ? candidate : (candidate.isEmpty || candidate == title ? "Notification" : candidate)

        return Item(
            appName: appName,
            title: title,
            body: texts.dropFirst().joined(separator: "\n"),
            date: Date(),
            appURL: appURL
        )
    }

    static func isTimestamp(_ text: String) -> Bool {
        text.range(of: #"^\d+\s?(m|h|min|mins|hr|hrs)( ago)?$"#, options: .regularExpression) != nil
    }

    private static func appURL(named name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
            return running.bundleURL
        }
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Presses the banner's Close action, if it offers one.
    private static func close(_ banner: AXUIElement) {
        var names: CFArray?
        guard AXUIElementCopyActionNames(banner, &names) == .success,
              let actions = names as? [String],
              let close = actions.first(where: { $0.localizedCaseInsensitiveContains("close") })
        else { return }
        AXUIElementPerformAction(banner, close as CFString)
    }

    // MARK: - AX helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Depth-first walk, bounded so a huge tree can't stall the main thread.
    private static func walk(_ element: AXUIElement, depth: Int, visit: (AXUIElement) -> Bool) {
        guard depth < 12, visit(element) else { return }
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        for child in children.prefix(40) {
            walk(child, depth: depth + 1, visit: visit)
        }
    }
}
