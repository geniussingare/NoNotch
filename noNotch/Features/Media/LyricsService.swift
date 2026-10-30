import Foundation
import Observation

/// Time-synced lyrics from LRCLIB (free, no key). Fetched once per track.
@MainActor
@Observable
final class LyricsService {
    struct Line: Equatable {
        let time: TimeInterval
        let text: String
    }

    private(set) var lines: [Line] = []
    @ObservationIgnored private var trackKey = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Called whenever the now-playing track changes.
    func load(for info: NowPlayingInfo?) {
        guard let info, !info.artist.isEmpty else {
            trackKey = ""
            lines = []
            return
        }
        let key = info.artist + "|" + info.title
        guard key != trackKey else { return }
        trackKey = key
        lines = []
        task?.cancel()
        task = Task { [weak self] in
            let fetched = await Self.fetch(artist: info.artist, title: info.title, album: info.album, duration: info.duration)
            guard !Task.isCancelled, let self, self.trackKey == key else { return }
            self.lines = fetched
        }
    }

    /// The line being sung at `position`, if any.
    func line(at position: TimeInterval) -> String? {
        guard let index = lines.lastIndex(where: { $0.time <= position + 0.3 }) else { return nil }
        let text = lines[index].text
        return text.isEmpty ? nil : text
    }

    private nonisolated static func fetch(artist: String, title: String, album: String, duration: TimeInterval) async -> [Line] {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("noNotch (https://github.com/)", forHTTPHeaderField: "User-Agent")
        struct Response: Decodable { let syncedLyrics: String? }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let synced = (try? JSONDecoder().decode(Response.self, from: data))?.syncedLyrics
        else { return [] }
        return parse(synced)
    }

    /// Parses LRC lines like `[01:23.45] text`.
    nonisolated static func parse(_ lrc: String) -> [Line] {
        lrc.split(separator: "\n").compactMap { raw in
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { return nil }
            let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { return nil }
            let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return Line(time: minutes * 60 + seconds, text: text)
        }
    }
}
