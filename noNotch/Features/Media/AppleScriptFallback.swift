import AppKit

/// Reads Music and Spotify over Apple Events when MediaRemote isn't available.
/// Polls once a second, and only while one of those apps is running.
@MainActor
final class AppleScriptFallback {
    private struct Player {
        let bundleID: String
        let name: String
        /// Spotify reports duration in milliseconds, Music in seconds.
        let durationDivisor: Double
    }

    private static let players = [
        Player(bundleID: "com.spotify.client", name: "Spotify", durationDivisor: 1000),
        Player(bundleID: "com.apple.Music", name: "Music", durationDivisor: 1),
    ]

    private let onUpdate: (NowPlayingInfo?) -> Void
    private var timer: Timer?
    private var lastArtworkKey = ""
    private var lastArtwork: Data?

    init(onUpdate: @escaping (NowPlayingInfo?) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.3
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func send(_ command: MediaCommand) {
        guard let player = activePlayer else { return }
        let verb = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .back15: "set player position to (player position - 15)"
        case .forward15: "set player position to (player position + 15)"
        }
        run("tell application \"\(player.name)\" to \(verb)")
        poll()
    }

    func seek(to seconds: TimeInterval) {
        guard let player = activePlayer else { return }
        run("tell application \"\(player.name)\" to set player position to \(seconds)")
    }

    private var activePlayer: Player? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.players.first { running.contains($0.bundleID) }
    }

    private func poll() {
        guard let player = activePlayer else {
            onUpdate(nil)
            return
        }
        let separator = "|§|"
        let script = """
        tell application "\(player.name)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "\(separator)" & (artist of t) & "\(separator)" & (album of t) & "\(separator)" & (duration of t) & "\(separator)" & player position & "\(separator)" & (player state as string)
        end tell
        """
        guard let output = run(script), !output.isEmpty else {
            onUpdate(nil)
            return
        }
        let parts = output.components(separatedBy: separator)
        guard parts.count == 6 else { return }

        let artworkKey = parts[0] + parts[1]
        if artworkKey != lastArtworkKey {
            lastArtworkKey = artworkKey
            lastArtwork = artwork(for: player)
        }

        onUpdate(NowPlayingInfo(
            bundleID: player.bundleID,
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            duration: (Double(parts[3]) ?? 0) / player.durationDivisor,
            elapsed: Double(parts[4]) ?? 0,
            isPlaying: parts[5] == "playing",
            artworkData: lastArtwork
        ))
    }

    private func artwork(for player: Player) -> Data? {
        if player.name == "Spotify",
           let urlString = run("tell application \"Spotify\" to return artwork url of current track"),
           let url = URL(string: urlString) {
            return try? Data(contentsOf: url)
        }
        let descriptor = NSAppleScript(source: "tell application \"Music\" to return raw data of artwork 1 of current track")?
            .executeAndReturnError(nil)
        return descriptor?.data
    }

    @discardableResult
    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}
