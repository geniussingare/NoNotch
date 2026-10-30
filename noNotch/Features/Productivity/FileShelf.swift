import AppKit
import Observation
import QuickLookThumbnailing

/// Files staged on the notch. Persisted as bookmarks so they survive relaunch.
@MainActor
@Observable
final class FileShelf {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var thumbnail: NSImage

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id && lhs.thumbnail === rhs.thumbnail }
    }

    private static let storageKey = "shelfBookmarks"
    private(set) var items: [Item] = []

    init() {
        let bookmarks = UserDefaults.standard.array(forKey: Self.storageKey) as? [Data] ?? []
        for bookmark in bookmarks {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                append(url)
            }
        }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            append(url)
        }
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    private func append(_ url: URL) {
        let item = Item(url: url, thumbnail: NSWorkspace.shared.icon(forFile: url.path))
        items.append(item)
        loadThumbnail(for: item)
    }

    private func loadThumbnail(for item: Item) {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: 96, height: 96), scale: 2, representationTypes: .thumbnail
        )
        let id = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in
                guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[index].thumbnail = image
            }
        }
    }

    private func persist() {
        let bookmarks = items.compactMap { try? $0.url.bookmarkData() }
        UserDefaults.standard.set(bookmarks, forKey: Self.storageKey)
    }
}
