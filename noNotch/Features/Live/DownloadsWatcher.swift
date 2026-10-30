import CoreServices
import Foundation

/// Watches ~/Downloads with FSEvents and reports in-progress browser downloads
/// (Safari `.download`, Chrome `.crdownload`, Firefox `.part`) and their completion.
@MainActor
final class DownloadsWatcher {
    private static let partialExtensions = ["download", "crdownload", "part"]

    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private let onActivity: (LiveActivity) -> Void
    private var stream: FSEventStreamRef?
    /// Partial file URL → last seen size.
    private var active: [URL: Int64] = [:]

    init(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
    }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<DownloadsWatcher>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated { watcher.scan() }
            },
            &context,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scan() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]
        )) ?? []
        let partials = contents.filter { Self.partialExtensions.contains($0.pathExtension.lowercased()) }

        for url in partials {
            let bytes = Self.size(of: url)
            active[url] = bytes
            onActivity(.download(name: Self.finalName(for: url), bytes: bytes, finished: false, url: nil))
        }

        for url in active.keys where !partials.contains(url) {
            let bytes = active.removeValue(forKey: url) ?? 0
            let finalURL = folder.appendingPathComponent(Self.finalName(for: url))
            // Cancelled downloads leave no final file behind.
            guard FileManager.default.fileExists(atPath: finalURL.path) else { continue }
            onActivity(.download(name: finalURL.lastPathComponent, bytes: max(bytes, Self.size(of: finalURL)), finished: true, url: finalURL))
        }
    }

    private static func finalName(for partial: URL) -> String {
        partial.deletingPathExtension().lastPathComponent
    }

    /// Safari's `.download` is a bundle; sum what's inside it.
    private static func size(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
