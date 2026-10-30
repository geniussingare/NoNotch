import AppKit
import SwiftUI
import XCTest
@testable import noNotch

// MARK: - Lyrics

final class LyricsParserTests: XCTestCase {
    func testParsesTimestampsAndText() {
        let lines = LyricsService.parse("""
        [00:12.50] First line
        [01:02.00]Second line
        [01:05.25]
        """)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time, 12.5, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[1].time, 62, accuracy: 0.001)
        XCTAssertEqual(lines[1].text, "Second line")
        XCTAssertEqual(lines[2].text, "")
    }

    func testIgnoresMetadataAndGarbage() {
        let lines = LyricsService.parse("[ar:Artist]\n[ti:Title]\nnot a lyric\n[00:01.00] ok")
        XCTAssertEqual(lines.map(\.text), ["ok"])
    }

    @MainActor
    func testCurrentLineLookup() {
        let service = LyricsService()
        XCTAssertNil(service.line(at: 10))
    }
}

// MARK: - Now Playing

final class NowPlayingInfoTests: XCTestCase {
    private func payload(_ extra: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "bundleIdentifier": "com.brave.Browser.helper",
            "parentApplicationBundleIdentifier": "com.brave.Browser",
            "title": "Video",
            "artist": "Channel",
            "playing": true,
            "durationMicros": 300_000_000,
            "elapsedTimeMicros": 60_000_000,
            "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            "playbackRate": 1,
        ]
        extra.forEach { json[$0] = $1 }
        return json
    }

    func testDecodesAdapterPayload() throws {
        let info = try XCTUnwrap(NowPlayingInfo(adapterPayload: payload()))
        XCTAssertEqual(info.title, "Video")
        XCTAssertEqual(info.appBundleID, "com.brave.Browser")
        XCTAssertEqual(info.duration, 300, accuracy: 0.001)
        XCTAssertEqual(info.elapsed, 60, accuracy: 0.001)
        XCTAssertTrue(info.isPlaying)
    }

    func testRejectsMissingTitle() {
        XCTAssertNil(NowPlayingInfo(adapterPayload: payload(["title": ""])))
        var json = payload()
        json.removeValue(forKey: "bundleIdentifier")
        XCTAssertNil(NowPlayingInfo(adapterPayload: json))
    }

    func testPositionExtrapolatesAndClamps() throws {
        var info = try XCTUnwrap(NowPlayingInfo(adapterPayload: payload()))
        XCTAssertEqual(info.position(at: info.timestamp.addingTimeInterval(10)), 70, accuracy: 0.01)
        XCTAssertEqual(info.position(at: info.timestamp.addingTimeInterval(10_000)), 300, accuracy: 0.01)
        info.isPlaying = false
        XCTAssertEqual(info.position(at: info.timestamp.addingTimeInterval(10)), 60, accuracy: 0.01)
    }
}

// MARK: - Live activities

@MainActor
final class ActivityCenterTests: XCTestCase {
    func testHigherPriorityReplacesAndLowerQueues() {
        let center = ActivityCenter()
        center.post(.power(level: 50, charging: true, pluggedIn: true))
        center.post(.hud(.brightness, value: 0.5))
        XCTAssertEqual(center.current, .hud(.brightness, value: 0.5))

        center.post(.bluetooth(name: "AirPods", symbol: "airpods", connected: true))
        XCTAssertEqual(center.current, .hud(.brightness, value: 0.5), "lower priority must wait")

        center.dismiss()
        XCTAssertEqual(center.current, .power(level: 50, charging: true, pluggedIn: true), "preempted activity resumes")
        center.dismiss()
        XCTAssertEqual(center.current, .bluetooth(name: "AirPods", symbol: "airpods", connected: true))
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testSameKindUpdatesInPlace() {
        let center = ActivityCenter()
        center.post(.hud(.volume(muted: false), value: 0.2))
        center.post(.hud(.volume(muted: false), value: 0.3))
        XCTAssertEqual(center.current, .hud(.volume(muted: false), value: 0.3))
        center.dismiss()
        XCTAssertNil(center.current, "an in-place update must not leave a stale copy queued")
    }

    func testExpiresAfterDuration() async throws {
        let center = ActivityCenter()
        center.post(.hud(.brightness, value: 1))
        try await Task.sleep(for: .milliseconds(1800))
        XCTAssertNil(center.current)
    }
}

// MARK: - Notch geometry & navigation

@MainActor
final class NotchViewModelTests: XCTestCase {
    private func makeModel(hasNotch: Bool = true) -> NotchViewModel {
        UserDefaults.standard.set(1.0, forKey: SettingsKey.panelScale)
        let model = NotchViewModel(services: Services())
        model.geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 185, height: 32),
            hasNotch: hasNotch
        )
        return model
    }

    func testIdleNotchMatchesHardware() {
        let model = makeModel()
        XCTAssertEqual(model.shapeSize.height, 32)
        XCTAssertEqual(model.shapeSize.width, 185 + model.topRadius * 2)
    }

    func testExpandedUsesTabSize() {
        let model = makeModel()
        model.expand(to: .media)
        XCTAssertEqual(model.shapeSize.width, 440 + model.topRadius * 2)
        XCTAssertEqual(model.shapeSize.height, 168)
        model.step(to: .shelf)
        XCTAssertEqual(model.shapeSize.width, 480 + model.topRadius * 2)
    }

    func testWingsWidenCollapsedShape() {
        let model = makeModel()
        model.services.activities.post(.hud(.brightness, value: 0.5))
        XCTAssertEqual(model.shapeSize.width, 185 + 60 * 2 + model.topRadius * 2)
    }

    func testNotificationBecomesBanner() {
        let model = makeModel()
        let item = NotificationMirror.Item(appName: "Messages", title: "Hi", body: "There", date: Date(), appURL: nil)
        model.services.activities.post(.notification(item))
        XCTAssertTrue(model.isNotificationBanner)
        XCTAssertEqual(model.shapeSize.height, 32 + 58)
    }

    func testPullCordOnlyWithoutNotch() {
        XCTAssertFalse(makeModel(hasNotch: true).showsPullCord)
        let external = makeModel(hasNotch: false)
        XCTAssertTrue(external.showsPullCord)
        external.expand()
        XCTAssertFalse(external.showsPullCord)
    }

    func testSwipeWrapsThroughBarTabs() {
        let model = makeModel()
        model.expand(to: .home)
        model.step(tab: -1)
        XCTAssertEqual(model.tab, NotchTab.barTabs.last)
        model.step(tab: 1)
        XCTAssertEqual(model.tab, .home)
    }

    func testTabsFitBesideTheNotch() {
        // Six 17pt tabs + spacing must fit the strip left of a 185pt notch at 440pt wide.
        let available = (440 - 185 - 8) / 2 - 14
        let needed = CGFloat(NotchTab.barTabs.count) * 17 + CGFloat(NotchTab.barTabs.count - 1)
        XCTAssertLessThanOrEqual(needed, CGFloat(available))
    }
}

// MARK: - Notifications

@MainActor
final class NotificationParsingTests: XCTestCase {
    func testTimestampNoiseIsRecognised() {
        XCTAssertTrue(NotificationMirror.isTimestamp("5m"))
        XCTAssertTrue(NotificationMirror.isTimestamp("2 h ago"))
        XCTAssertTrue(NotificationMirror.isTimestamp("12 mins"))
        XCTAssertFalse(NotificationMirror.isTimestamp("Meeting moved to 5"))
        XCTAssertFalse(NotificationMirror.isTimestamp("Hello"))
    }
}

// MARK: - Palette & formatting

final class PaletteAndFormatTests: XCTestCase {
    func testPaletteFindsDominantHue() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let data = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let palette = ArtworkPalette.extract(from: data)
        XCTAssertGreaterThan(palette.primary.r, palette.primary.g)
        XCTAssertGreaterThan(palette.primary.r, palette.primary.b)
    }

    func testGarbageArtworkFallsBack() {
        XCTAssertEqual(ArtworkPalette.extract(from: Data([1, 2, 3])), .fallback)
    }

    func testTimeFormatting() {
        XCTAssertEqual(Format.time(0), "0:00")
        XCTAssertEqual(Format.time(65), "1:05")
        XCTAssertEqual(Format.time(3725), "1:02:05")
        XCTAssertEqual(Format.time(-.infinity), "0:00")
        XCTAssertEqual(Format.time(.nan), "0:00")
    }
}

@MainActor
final class PanelScaleTests: XCTestCase {
    func testScaleShrinksExpandedPanel() {
        UserDefaults.standard.set(0.75, forKey: SettingsKey.panelScale)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKey.panelScale) }
        let model = NotchViewModel(services: Services())
        model.geometry = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        model.expand(to: .media)
        XCTAssertEqual(model.shapeSize.width, 440 * 0.75 + model.topRadius * 2, accuracy: 0.01)
        XCTAssertEqual(model.shapeSize.height, 168 * 0.75, accuracy: 0.01)
    }

    func testDefaultIsCompact() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.panelScale)
        XCTAssertEqual(UserDefaults.standard.panelScale, 0.85)
    }
}

// MARK: - Visual snapshots (written to NONOTCH_SNAPSHOT_DIR for review)

@MainActor
final class MediaLayoutSnapshotTests: XCTestCase {
    func testLongTitleKeepsArtworkAndControlsVisible() throws {
        let services = Services()
        let model = NotchViewModel(services: services)
        model.geometry = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        services.media.inject(NowPlayingInfo(
            bundleID: "com.google.Chrome",
            title: "Tu Jo Mila FULL VIDEO Song - Atif Aslam Pritam | Bajrangi Bhaijaan | Salman Khan, Harshaali Malhotra",
            artist: "T-Series",
            album: "",
            duration: 270,
            elapsed: 75,
            isPlaying: true,
            artworkData: nil
        ))

        let size = NotchTab.media.contentSize
        let view = MediaView(viewModel: model)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(width: size.width, height: size.height - 32)
            .background(.black)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, size.width, accuracy: 1, "media panel must not grow wider than its tab size")

        if let dir = ProcessInfo.processInfo.environment["NONOTCH_SNAPSHOT_DIR"],
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("media-long-title.png"))
        }
    }
}

@MainActor
final class AllTabsSnapshotTests: XCTestCase {
    func testEveryTabFitsItsSize() throws {
        let services = Services()
        let model = NotchViewModel(services: services)
        model.geometry = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        services.media.inject(NowPlayingInfo(
            bundleID: "com.spotify.client", title: "A Very Long Song Title That Keeps Going And Going Forever",
            artist: "Artist Name", album: "Album", duration: 200, elapsed: 50, isPlaying: true, artworkData: nil
        ))
        let dir = ProcessInfo.processInfo.environment["NONOTCH_SNAPSHOT_DIR"]

        for tab in NotchTab.allCases where tab != .mirror {
            model.tab = tab
            let size = tab.contentSize
            let view = ExpandedView(viewModel: model)
                .frame(width: size.width, height: size.height)
                .background(.black)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "\(tab) failed to render")
            XCTAssertEqual(image.size.width, size.width, accuracy: 1, "\(tab) grew wider than its size")
            XCTAssertEqual(image.size.height, size.height, accuracy: 1, "\(tab) grew taller than its size")
            if let dir, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("tab-\(tab.rawValue).png"))
            }
        }
    }
}
