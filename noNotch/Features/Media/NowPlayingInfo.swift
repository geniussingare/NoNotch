import Foundation

/// Snapshot of what's playing, decoded off the main thread.
struct NowPlayingInfo: Equatable, Sendable {
    var bundleID: String
    var parentBundleID: String?
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    /// Elapsed time at `timestamp`; extrapolate with `playbackRate` for the live position.
    var elapsed: TimeInterval
    var timestamp: Date
    var isPlaying: Bool
    var playbackRate: Double
    var artworkData: Data?
    var mediaType: String?

    /// App that owns the session; browsers report a helper process as the child.
    var appBundleID: String { parentBundleID ?? bundleID }

    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsed }
        let live = elapsed + date.timeIntervalSince(timestamp) * max(playbackRate, 1)
        return duration > 0 ? min(live, duration) : live
    }

    /// Decodes one `--micros --no-diff` payload from mediaremote-adapter.
    init?(adapterPayload json: [String: Any]) {
        guard let bundleID = json["bundleIdentifier"] as? String,
              let title = json["title"] as? String, !title.isEmpty
        else { return nil }

        func seconds(_ key: String) -> TimeInterval {
            (json[key] as? NSNumber).map { $0.doubleValue / 1_000_000 } ?? 0
        }

        self.bundleID = bundleID
        parentBundleID = json["parentApplicationBundleIdentifier"] as? String
        self.title = title
        artist = json["artist"] as? String ?? ""
        album = json["album"] as? String ?? ""
        duration = seconds("durationMicros")
        elapsed = seconds("elapsedTimeMicros")
        let stamp = seconds("timestampEpochMicros")
        timestamp = stamp > 0 ? Date(timeIntervalSince1970: stamp) : Date()
        isPlaying = json["playing"] as? Bool ?? false
        playbackRate = (json["playbackRate"] as? NSNumber)?.doubleValue ?? (isPlaying ? 1 : 0)
        artworkData = (json["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        mediaType = json["mediaType"] as? String
    }

    init(bundleID: String, title: String, artist: String, album: String,
         duration: TimeInterval, elapsed: TimeInterval, isPlaying: Bool, artworkData: Data?) {
        self.bundleID = bundleID
        parentBundleID = nil
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        timestamp = Date()
        self.isPlaying = isPlaying
        playbackRate = isPlaying ? 1 : 0
        self.artworkData = artworkData
        mediaType = nil
    }
}

enum MediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case next = 4
    case previous = 5
    case back15 = 12
    case forward15 = 13
}
