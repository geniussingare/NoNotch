import AppKit
import Observation

/// One-click setup of noNotch's MCP server in Claude Code, the Claude app and Cursor.
@MainActor
@Observable
final class AgentConnector {
    enum Client: String, CaseIterable, Identifiable {
        case claudeCode
        case claudeApp
        case cursor

        var id: String { rawValue }

        var title: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .claudeApp: "Claude app"
            case .cursor: "Cursor"
            }
        }

        var detail: String {
            switch self {
            case .claudeCode: "Available in every folder (user scope)"
            case .claudeApp: "Claude for Mac, after a restart"
            case .cursor: "All Cursor workspaces, after a restart"
            }
        }

        var symbol: String {
            switch self {
            case .claudeCode: "terminal.fill"
            case .claudeApp: "bubble.left.and.text.bubble.right.fill"
            case .cursor: "cursorarrow.rays"
            }
        }

        /// Desktop apps that must restart to load a new server.
        var bundleID: String? {
            switch self {
            case .claudeCode: nil
            case .claudeApp: "com.anthropic.claudefordesktop"
            case .cursor: "com.todesktop.230313mzl4w4u92"
            }
        }

        var configURL: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .claudeCode: return home.appendingPathComponent(".claude.json")
            case .claudeApp: return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
            case .cursor: return home.appendingPathComponent(".cursor/mcp.json")
            }
        }
    }

    static let serverName = "nonotch"

    /// Per-client message after the last action ("Connected", an error…).
    private(set) var messages: [Client: String] = [:]
    private(set) var busy: Set<Client> = []
    /// Bumped to re-read config files.
    private(set) var revision = 0

    /// The bundled stdio server.
    var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nonotch-mcp")
    }

    var helperExists: Bool { FileManager.default.isExecutableFile(atPath: helperURL.path) }

    // MARK: - Status

    func isConnected(_ client: Client) -> Bool {
        _ = revision
        guard let servers = Self.read(client.configURL)?["mcpServers"] as? [String: Any],
              let entry = servers[Self.serverName] as? [String: Any] else { return false }
        return entry["command"] as? String == helperURL.path
    }

    /// Configured, but pointing at an older copy of noNotch.
    func isStale(_ client: Client) -> Bool {
        _ = revision
        guard let servers = Self.read(client.configURL)?["mcpServers"] as? [String: Any],
              let entry = servers[Self.serverName] as? [String: Any] else { return false }
        return entry["command"] as? String != helperURL.path
    }

    func isRunning(_ client: Client) -> Bool {
        guard let bundleID = client.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func isInstalled(_ client: Client) -> Bool {
        switch client {
        case .claudeCode: return Self.claudeCLI() != nil || FileManager.default.fileExists(atPath: client.configURL.path)
        default: return client.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } != nil
        }
    }

    // MARK: - Actions

    func connect(_ client: Client) {
        guard helperExists else {
            messages[client] = "The MCP helper is missing from noNotch.app."
            return
        }
        busy.insert(client)
        Task {
            defer { busy.remove(client); revision += 1 }
            do {
                if client == .claudeCode, let cli = Self.claudeCLI() {
                    // The CLI owns ~/.claude.json; let it write the entry.
                    _ = await Self.run(cli, ["mcp", "remove", "--scope", "user", Self.serverName])
                    let result = await Self.run(cli, ["mcp", "add", "--scope", "user", Self.serverName, "--", helperURL.path])
                    if result != 0 { try write(client) }
                } else {
                    try write(client)
                }
                messages[client] = client.bundleID != nil && isRunning(client) ? "Connected. Restart to load it." : "Connected"
            } catch {
                messages[client] = error.localizedDescription
            }
        }
    }

    func disconnect(_ client: Client) {
        busy.insert(client)
        Task {
            defer { busy.remove(client); revision += 1 }
            if client == .claudeCode, let cli = Self.claudeCLI() {
                _ = await Self.run(cli, ["mcp", "remove", "--scope", "user", Self.serverName])
            }
            do {
                try update(client.configURL) { servers in servers.removeValue(forKey: Self.serverName) }
                messages[client] = "Disconnected"
            } catch {
                messages[client] = error.localizedDescription
            }
        }
    }

    /// Quits and reopens a desktop client so it picks up the server.
    func restart(_ client: Client) {
        guard let bundleID = client.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        busy.insert(client)
        Task {
            defer { busy.remove(client) }
            apps.forEach { $0.terminate() }
            for _ in 0..<50 where apps.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            messages[client] = "Restarted"
        }
    }

    /// Restarts every connected desktop client that's open.
    func restartOpenClients() {
        for client in Client.allCases where client.bundleID != nil && isRunning(client) && isConnected(client) {
            restart(client)
        }
    }

    // MARK: - Config files

    private func write(_ client: Client) throws {
        var entry: [String: Any] = ["command": helperURL.path, "args": [String]()]
        if client == .claudeCode { entry["type"] = "stdio" }
        try update(client.configURL) { servers in servers[Self.serverName] = entry }
    }

    /// Merges into `mcpServers`, keeping everything else and a one-time backup.
    private func update(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: url.path) {
            guard let existing = Self.read(url) else {
                throw NSError(domain: "noNotch", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) isn't valid JSON; fix it or remove it first."])
            }
            root = existing
            let backup = url.appendingPathExtension("nonotch-backup")
            if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        change(&servers)
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Claude Code CLI

    private static func claudeCLI() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    private static func run(_ executable: URL, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    // MARK: - Prompts

    static let suggestions = [
        "What's on my noNotch list today?",
        "Add “call mom tomorrow at 5pm #family !high” to noNotch",
        "Plan my day: order today's tasks by priority and move the rest to tomorrow",
        "Start a 25-minute focus on my top task",
        "Summarise my week from noNotch insights",
        "Turn these meeting notes into noNotch tasks with steps",
    ]
}
