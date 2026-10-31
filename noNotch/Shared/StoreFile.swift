import Foundation

/// `store.json` in Application Support, shared by the app and the MCP helper.
/// Every write happens under an exclusive `flock`, applied to the freshest copy on disk,
/// so the two processes never overwrite each other's changes.
struct StoreFile: Sendable {
    let url: URL

    /// `NONOTCH_STORE` overrides the location (used by tests and helper smoke tests).
    static let standard = StoreFile(
        url: ProcessInfo.processInfo.environment["NONOTCH_STORE"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("noNotch", isDirectory: true)
                .appendingPathComponent("store.json")
    )

    var directory: URL { url.deletingLastPathComponent() }
    private var lockURL: URL { url.appendingPathExtension("lock") }

    func load() -> StoreData {
        guard let data = try? Data(contentsOf: url) else { return StoreData() }
        return (try? Self.decoder.decode(StoreData.self, from: data)) ?? StoreData()
    }

    /// Applies `change` to the current file contents and saves only if something changed.
    @discardableResult
    func update<T>(_ change: (inout StoreData) throws -> T) rethrows -> (StoreData, T) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        var data = load()
        let before = data
        let result = try change(&data)
        if data != before, let encoded = try? Self.encoder.encode(data) {
            try? encoded.write(to: url, options: .atomic)
        }
        return (data, result)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Exact Double timestamps: a round-trip must compare equal to what was saved.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        JSONDecoder()
    }()
}
