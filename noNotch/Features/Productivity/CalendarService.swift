import AppKit
import EventKit
import Observation

/// Next calendar event with a meeting-link detector and a 5‑minute heads-up.
@MainActor
@Observable
final class CalendarService {
    struct Event: Equatable, Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: NSColor
        let meetingURL: URL?
        let location: String?
        let isAllDay: Bool
    }

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"https://[\w.-]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com)/[^\s<>"]+"#,
        options: .caseInsensitive
    )

    private(set) var upcoming: [Event] = []
    private(set) var authorized = false
    /// Events for the month shown in the calendar grid, keyed by start of day.
    private(set) var monthEvents: [Date: [Event]] = [:]

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var reminder: Task<Void, Never>?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var onActivity: (LiveActivity) -> Void = { _ in }
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var begun = false

    var next: Event? { upcoming.first }

    func start(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if authorized, !begun { begin() }
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            authorized = granted
            if granted, !begun { begin() }
        }
    }

    private func begin() {
        begun = true
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Refresh every 5 minutes so "now" rolls forward; cheap and tolerant.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        refreshTimer?.tolerance = 30
        reload()
    }

    func reload() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60 * 30), end: now.addingTimeInterval(60 * 60 * 24), calendars: nil)
        upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map(Self.makeEvent)
        scheduleReminder()
    }

    func loadMonth(containing date: Date) {
        guard authorized, let interval = Calendar.current.dateInterval(of: .month, for: date) else { return }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        var grouped: [Date: [Event]] = [:]
        for event in store.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate }) {
            grouped[Calendar.current.startOfDay(for: event.startDate), default: []].append(Self.makeEvent(event))
        }
        monthEvents = grouped
    }

    private static func makeEvent(_ event: EKEvent) -> Event {
        Event(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            color: event.calendar?.color ?? .systemBlue,
            meetingURL: meetingURL(in: event),
            location: event.location,
            isAllDay: event.isAllDay
        )
    }

    func join(_ event: Event) {
        if let url = event.meetingURL { NSWorkspace.shared.open(url) }
    }

    private func scheduleReminder() {
        reminder?.cancel()
        guard let event = upcoming.first(where: { $0.start > Date() && !announced.contains($0.id) }) else { return }
        let fireAt = event.start.addingTimeInterval(-5 * 60)
        reminder = Task { [weak self] in
            let delay = max(fireAt.timeIntervalSinceNow, 0)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            announced.insert(event.id)
            onActivity(.event(title: event.title, minutes: max(Int(event.start.timeIntervalSinceNow / 60), 0)))
            scheduleReminder()
        }
    }

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, meetingPattern.firstMatch(in: url.absoluteString, range: NSRange(url.absoluteString.startIndex..., in: url.absoluteString)) != nil {
            return url
        }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            if let match = meetingPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return URL(string: String(text[range]))
            }
        }
        return nil
    }
}
