import AppKit
import Observation

/// Compares this build with the latest GitHub release, once a day and on request.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let repository = "geniussingare/NoNotch"
    static var releasesURL: URL { URL(string: "https://github.com/\(repository)/releases/latest")! }
    static var issuesURL: URL { URL(string: "https://github.com/\(repository)/issues/new")! }

    private(set) var latest: String?
    private(set) var checking = false

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var updateAvailable: Bool { latest.map { Self.isNewer($0, than: current) } ?? false }

    @ObservationIgnored private var timer: Timer?

    func start() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.check() } }
        }
        timer?.tolerance = 3600
    }

    /// Menu bar "Check for Updates…": checks now and says what it found.
    func checkInteractively() {
        Task {
            await check()
            let alert = NSAlert()
            if updateAvailable, let latest {
                alert.messageText = "noNotch \(latest) is available"
                alert.informativeText = "You have \(current)."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
            } else if latest == nil {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Check your connection and try again."
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "noNotch \(current) is the latest version."
            }
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn, updateAvailable { openDownload() }
        }
    }

    func openDownload() { NSWorkspace.shared.open(Self.releasesURL) }

    func reportBug() {
        var components = URLComponents(url: Self.issuesURL, resolvingAgainstBaseURL: false)!
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        components.queryItems = [
            URLQueryItem(name: "title", value: "Bug: "),
            URLQueryItem(name: "body", value: "**What happened**\n\n\n**Steps to reproduce**\n\n\n---\nnoNotch \(current) · macOS \(os)"),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return }
        latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    /// Numeric dotted-version comparison ("0.10.0" > "0.9.2").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
