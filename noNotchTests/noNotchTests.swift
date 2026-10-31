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
        // Seven 15pt tabs must fit the strip left of a 185pt notch at 440pt wide.
        let available = (440 - 185 - 8) / 2 - 14
        let needed = CGFloat(NotchTab.barTabs.count) * 15
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

// MARK: - Tasks

final class TaskParserTests: XCTestCase {
    private let calendar = Calendar.current

    func testDateTimePriorityAndProject() throws {
        let now = Date()
        let parsed = TaskParser.parse("call mom tomorrow at 5pm #family !high", now: now)
        XCTAssertEqual(parsed.title, "Call mom")
        XCTAssertEqual(parsed.project, "family")
        XCTAssertEqual(parsed.priority, .high)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(parsed.day, tomorrow)
        let due = try XCTUnwrap(parsed.due)
        XCTAssertEqual(calendar.component(.hour, from: due), 17)
    }

    func testDayWithoutTimeHasNoReminder() {
        let parsed = TaskParser.parse("pay rent tomorrow")
        XCTAssertEqual(parsed.title, "Pay rent")
        XCTAssertNotNil(parsed.day)
        XCTAssertNil(parsed.due)
    }

    func testRepeats() {
        XCTAssertEqual(TaskParser.parse("water plants every day").repeatRule, .daily)
        XCTAssertEqual(TaskParser.parse("standup every weekday").repeatRule, .weekdays)
        XCTAssertEqual(TaskParser.parse("rent monthly").repeatRule, .monthly)
        let gym = TaskParser.parse("gym every monday")
        XCTAssertEqual(gym.repeatRule, .weekly([2]))
        XCTAssertEqual(gym.title, "Gym")
        XCTAssertEqual(gym.day.map { calendar.component(.weekday, from: $0) }, 2)
    }

    func testPriorityShorthands() {
        XCTAssertEqual(TaskParser.parse("a p1").priority, .high)
        XCTAssertEqual(TaskParser.parse("a !!").priority, .medium)
        XCTAssertEqual(TaskParser.parse("a !low").priority, .low)
        XCTAssertNil(TaskParser.parse("wow!").priority)
    }

    func testRemindMePrefixAndPlainText() {
        XCTAssertEqual(TaskParser.parse("remind me to stretch").title, "Stretch")
        let plain = TaskParser.parse("buy milk")
        XCTAssertEqual(plain.title, "Buy milk")
        XCTAssertFalse(plain.hasMetadata)
    }
}

final class StoreDataTests: XCTestCase {
    private let calendar = Calendar.current

    func testRollOverMovesUnfinishedWork() {
        var data = StoreData()
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        var open = TaskItem(title: "open"); open.day = yesterday
        var done = TaskItem(title: "done"); done.day = yesterday; done.done = yesterday
        data.tasks = [open, done]
        XCTAssertTrue(data.rollOver(now: now))
        XCTAssertEqual(data.task(open.id)?.day, calendar.startOfDay(for: now))
        XCTAssertEqual(data.task(done.id)?.day, yesterday, "finished tasks stay where they were")
        XCTAssertEqual(data.todayTasks(now).map(\.id), [open.id])
    }

    func testCompletingRepeatSpawnsNext() {
        var data = StoreData()
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let added = data.add(ParsedTask(title: "water", day: today, due: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today), repeatRule: .daily), now: now)
        data.setDone(added.id, true, now: now)
        XCTAssertEqual(data.tasks.count, 2)
        let next = data.tasks.first { !$0.isDone }!
        XCTAssertEqual(next.day, calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(next.due.map { calendar.component(.minute, from: $0) }, 30)
        XCTAssertEqual(next.repeatRule, .daily)
        XCTAssertNil(data.task(added.id)?.repeatRule)
    }

    func testMoveReorders() {
        var data = StoreData()
        let a = data.add(ParsedTask(title: "a")), b = data.add(ParsedTask(title: "b")), c = data.add(ParsedTask(title: "c"))
        data.move(c.id, before: a.id)
        XCTAssertEqual(data.todayTasks().map(\.title), ["c", "a", "b"])
        _ = b
    }

    func testFileRoundTripAndLockedUpdate() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = StoreFile(url: dir.appendingPathComponent("store.json"))
        let (saved, task) = file.update { $0.add(ParsedTask(title: "persist", priority: .high)) }
        XCTAssertEqual(file.load(), saved)
        XCTAssertEqual(file.load().task(task.id)?.priority, .high)
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Focus, insights, home layout

@MainActor
final class FocusTimerTests: XCTestCase {
    func testCountdownAddFiveAndPause() {
        let timer = FocusTimer()
        timer.start(minutes: 10)
        XCTAssertTrue(timer.isRunning)
        timer.addFiveMinutes()
        XCTAssertEqual(timer.remaining(at: Date()), 15 * 60, accuracy: 2)
        timer.pause()
        XCTAssertTrue(timer.isPaused)
        let paused = timer.remaining(at: Date())
        XCTAssertEqual(timer.remaining(at: Date().addingTimeInterval(120)), paused, "paused time doesn't move")
        timer.resume()
        XCTAssertTrue(timer.isRunning)
        timer.reset()
        XCTAssertFalse(timer.isActive)
    }

    func testStopwatchCountsUp() {
        let timer = FocusTimer()
        timer.start(mode: .stopwatch)
        XCTAssertEqual(timer.display(at: Date().addingTimeInterval(90)), 90, accuracy: 2)
        timer.addFiveMinutes()
        XCTAssertEqual(timer.display(at: Date().addingTimeInterval(90)), 90, accuracy: 2, "+5 only applies to countdowns")
        timer.reset()
    }
}

final class InsightsAndLayoutTests: XCTestCase {
    func testWeekStats() {
        var data = StoreData()
        let now = Date()
        var task = TaskItem(title: "a"); task.done = now
        var old = TaskItem(title: "old"); old.done = now.addingTimeInterval(-30 * 86400)
        data.tasks = [task, old]
        data.sessions = [FocusSession(start: now.addingTimeInterval(-600), duration: 1500)]
        let stats = InsightStats(data: data, now: now)
        XCTAssertEqual(stats.days.count, 7)
        XCTAssertEqual(stats.tasksDone, 1)
        XCTAssertEqual(stats.focusSeconds, 1500)
        XCTAssertEqual(stats.days.last?.tasks, 1)
        XCTAssertNotNil(stats.peakHour)
    }

    func testHomeWidthFollowsCards() {
        var cards = HomeCard.defaults
        let base = HomeCard.panelWidth(cards)
        cards[3].visible = true
        XCTAssertGreaterThan(HomeCard.panelWidth(cards), base)
        XCTAssertLessThanOrEqual(HomeCard.panelWidth(cards.map { var c = $0; c.visible = true; c.wide = true; return c }), 640)
    }
}

// MARK: - Reminders mapping & suggestions

@MainActor
final class RemindersMappingTests: XCTestCase {
    func testPriorityRoundTrips() {
        for priority in TaskPriority.allCases {
            XCTAssertEqual(RemindersSync.priority(fromEventKit: RemindersSync.eventKitPriority(priority)), priority)
        }
    }

    func testFieldsIgnoreSeconds() {
        var task = TaskItem(title: "a")
        task.due = Date(timeIntervalSinceReferenceDate: 600 + 42)
        var copy = task
        RemindersSync.Fields(title: "a", notes: "", done: false, priority: .none, day: nil, due: Date(timeIntervalSinceReferenceDate: 600)).apply(to: &copy)
        XCTAssertEqual(copy.due, task.due, "a minute-rounded copy must not count as a change")
    }

    func testDeletingSyncedTaskLeavesTombstone() {
        var data = StoreData()
        var task = TaskItem(title: "a"); task.remindersID = "R1"
        data.tasks = [task]
        data.delete(task.id)
        XCTAssertEqual(data.removedReminders, ["R1"])
    }

    func testEmptySuggestion() {
        XCTAssertTrue(TaskSuggestion(priority: TaskPriority.none, project: nil).isEmpty)
        XCTAssertFalse(TaskSuggestion(priority: .high, project: nil).isEmpty)
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testVersionOrdering() {
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.2"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.2.0"))
    }
}
