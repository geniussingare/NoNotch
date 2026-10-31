import AppKit
import Observation
import SwiftUI

enum NotchState: Equatable {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case tasks
    case media
    case controls
    case notes
    case shelf
    case clipboard
    /// Sub-pages opened from other tabs; not in the tab bar.
    case calendar
    case mirror
    case notifications
    case taskDetail
    case upcoming
    case taskDue
    case insights

    var id: String { rawValue }

    static let barTabs: [NotchTab] = [.home, .tasks, .media, .controls, .notes, .shelf, .clipboard]

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .tasks: "checklist"
        case .media: "play.circle.fill"
        case .controls: "switch.2"
        case .notes: "note.text"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .calendar: "calendar"
        case .mirror: "person.crop.square"
        case .notifications: "bell.fill"
        case .taskDetail: "checklist"
        case .upcoming: "calendar.day.timeline.left"
        case .taskDue: "bell.badge.fill"
        case .insights: "chart.bar.xaxis"
        }
    }

    /// Expanded size including the notch strip; each tab is sized to its content.
    var contentSize: CGSize {
        switch self {
        case .media: CGSize(width: 440, height: 168)
        case .home: CGSize(width: HomeCard.panelWidth(HomeCard.load()), height: 150)
        case .controls: CGSize(width: 440, height: 150)
        case .notes: CGSize(width: 440, height: 170)
        case .shelf, .clipboard: CGSize(width: 480, height: 150)
        case .calendar: CGSize(width: 460, height: 196)
        case .mirror: CGSize(width: 340, height: 230)
        case .notifications: CGSize(width: 440, height: 200)
        case .tasks: CGSize(width: 460, height: 210)
        case .taskDetail: CGSize(width: 460, height: 236)
        case .upcoming: CGSize(width: 460, height: 214)
        case .taskDue: CGSize(width: 400, height: 124)
        case .insights: CGSize(width: 480, height: 222)
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .media: "Now Playing"
        case .controls: "Controls"
        case .notes: "Notes"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .calendar: "Calendar"
        case .mirror: "Mirror"
        case .notifications: "Notifications"
        case .tasks: "Tasks"
        case .taskDetail: "Task"
        case .upcoming: "Upcoming"
        case .taskDue: "Reminder"
        case .insights: "Insights"
        }
    }
}

/// What the collapsed notch shows beside the hardware cut-out, if anything.
enum WingContent: Equatable {
    case activity(LiveActivity)
    case focus
    case media

    /// Width of each side wing.
    var width: CGFloat {
        switch self {
        case .media: 32
        case .focus: 52
        case .activity(let activity):
            switch activity {
            case .hud: 60
            case .power, .lowBattery: 55
            case .download: 62
            case .bluetooth: 70
            case .event, .timerFinished: 70
            case .eyeBreak: 64
            case .taskDue: 70
            case .welcome: 64
            case .notification: 0
            }
        }
    }
}

@MainActor
@Observable
final class NotchViewModel {
    /// Opening: a gentle spring. Closing: crisp, no bounce-back.
    // With Reduce Motion on, morphs become short cross-fades instead of springs.
    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var spring: Animation { reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.45, dampingFraction: 0.74) }
    static var closeSpring: Animation { reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.32, dampingFraction: 0.95) }
    static var snappy: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.8) }

    let services: Services

    private(set) var state: NotchState = .collapsed
    var tab: NotchTab = .home
    var geometry = NotchGeometry(screenFrame: .zero, notchSize: CGSize(width: 190, height: 32), hasNotch: false)
    /// Pointer is resting on the collapsed notch: it "breathes" outward in anticipation.
    var isHovering = false
    /// A file drag is over the notch.
    var isDropTargeted = false

    /// Task open in the detail page.
    var selectedTaskID: UUID?
    /// Task whose reminder is showing on the Reminder page.
    var dueTaskID: UUID?

    @ObservationIgnored var openSettings: () -> Void = {}

    init(services: Services) {
        self.services = services
        services.onTaskDue = { [weak self] task in self?.presentDue(task) }
    }

    /// A reminder came due: chime, then open the notch on it.
    func presentDue(_ task: TaskItem) {
        NSSound(named: "Glass")?.play()
        dueTaskID = task.id
        services.activities.post(.taskDue(id: task.id, title: task.title))
        expand(to: .taskDue)
    }

    func showTask(_ id: UUID) {
        selectedTaskID = id
        step(to: .taskDetail)
    }

    var isExpanded: Bool { state == .expanded }

    /// Screens without a notch show a hanging pull-cord instead of a black island
    /// until there's something to show.
    var showsPullCord: Bool { !geometry.hasNotch && !isExpanded && wing == nil }

    var wing: WingContent? {
        if let activity = services.activities.current { return .activity(activity) }
        // A running or paused focus timer stays beside the notch.
        if services.focus.isActive { return .focus }
        if services.media.isPlaying, !services.media.isSourceFrontmost { return .media }
        return nil
    }

    var isNotificationBanner: Bool {
        if !isExpanded, case .activity(.notification) = wing { return true }
        return false
    }

    var topRadius: CGFloat { isExpanded || isNotificationBanner ? 12 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 24 : (isNotificationBanner ? 22 : (wing == nil ? 10 : 12)) }

    /// User-adjustable panel scale (Settings → Panel size).
    var panelScale: CGFloat {
        CGFloat(UserDefaults.standard.panelScale)
    }

    /// Full frame of the notch shape, ears included.
    var shapeSize: CGSize {
        let notch = geometry.notchSize
        switch state {
        case .collapsed where showsPullCord:
            return CGSize(width: 60, height: 40)
        case .collapsed where isNotificationBanner:
            // iOS-style banner: the island grows down and out to show the message.
            return CGSize(width: 400 * panelScale + topRadius * 2, height: notch.height + 58)
        case .collapsed:
            let wingWidth = wing.map { $0.width * 2 } ?? 0
            let breath: CGFloat = isHovering ? 6 : 0
            return CGSize(
                width: notch.width + wingWidth + breath + topRadius * 2,
                height: notch.height + (isHovering ? 2 : 0)
            )
        case .expanded:
            let content = tab.contentSize
            return CGSize(
                width: content.width * panelScale + topRadius * 2,
                height: (content.height + (isDropTargeted ? 8 : 0)) * panelScale
            )
        }
    }

    /// Accent used across the UI: artwork colour while media is up, else the system accent.
    var accent: Color {
        services.media.hasMedia ? services.media.palette.primary.color : .accentColor
    }

    func expand(to tab: NotchTab? = nil) {
        if let tab {
            self.tab = tab
        } else if state == .collapsed {
            self.tab = defaultTab
        }
        guard state != .expanded else { return }
        if UserDefaults.standard.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(Self.spring) {
            isHovering = false
            state = .expanded
        }
    }

    func collapse() {
        guard state != .collapsed else { return }
        withAnimation(Self.closeSpring) {
            state = .collapsed
            isDropTargeted = false
        }
    }

    func step(to tab: NotchTab) {
        withAnimation(Self.spring) { self.tab = tab }
    }

    /// Two-finger swipe / arrow navigation between tabs.
    func step(tab offset: Int) {
        let tabs = NotchTab.barTabs
        guard let index = tabs.firstIndex(of: tab) else { return }
        let next = tabs[(index + offset + tabs.count) % tabs.count]
        withAnimation(Self.spring) { tab = next }
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering, !isExpanded else { return }
        withAnimation(Self.snappy) { isHovering = hovering }
    }

    /// Open on whatever is most relevant right now.
    private var defaultTab: NotchTab {
        if case .activity(.download(_, _, true, _)) = wing { return .shelf }
        if case .activity(.hud) = wing { return .controls }
        if case .activity(.notification) = wing { return .notifications }
        if case .activity(.taskDue(let id, _)) = wing {
            dueTaskID = id
            return .taskDue
        }
        return services.media.hasMedia ? .media : .home
    }
}
