import Foundation

/// What `TaskParser` understood from a typed or dictated phrase.
struct ParsedTask: Equatable, Sendable {
    var title: String
    var day: Date?
    var due: Date?
    var repeatRule: RepeatRule?
    var priority: TaskPriority?
    var project: String?

    var hasMetadata: Bool { day != nil || due != nil || repeatRule != nil || priority != nil || project != nil }
}

/// Turns "call mom tomorrow at 5pm every week #family !high" into a task.
///
/// Supported: dates and times (via `NSDataDetector`), `every day|weekday|week|month|<weekday>`,
/// `daily|weekly|monthly`, priority `!high` `!med` `!low` `!!!` `p1`–`p3`, projects `#name`,
/// and a leading "remind me to".
enum TaskParser {
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedTask {
        var text = " " + input.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        var result = ParsedTask(title: "")

        if let match = firstMatch(#"(?<=\s)#([\p{L}\p{N}_-]+)(?=\s)"#, in: text) {
            result.project = match.groups[0]
            text = text.replacingCharacters(in: match.range, with: " ")
        }

        if let match = firstMatch(#"(?<=\s)(!{1,3}|![a-zA-Z0-9]+|[pP][123])(?=\s)"#, in: text),
           let priority = priority(from: match.groups[0]) {
            result.priority = priority
            text = text.replacingCharacters(in: match.range, with: " ")
        }

        var repeatWeekday: Int?
        if let match = firstMatch(#"(?i)\b(?:every\s+(day|weekday|week|month|sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?|(daily|weekly|monthly))\b"#, in: text) {
            let word = (match.groups[0].isEmpty ? match.groups[1] : match.groups[0]).lowercased()
            switch word {
            case "day", "daily": result.repeatRule = .daily
            case "weekday": result.repeatRule = .weekdays
            case "month", "monthly": result.repeatRule = .monthly
            case "week", "weekly": result.repeatRule = .weekly([])
            default:
                if let index = weekdayIndex(word, calendar: calendar) {
                    repeatWeekday = index
                    result.repeatRule = .weekly([index])
                }
            }
            text = text.replacingCharacters(in: match.range, with: " ")
        }

        if let match = firstMatch(#"(?i)^\s*remind\s+me\s+(?:to\s+)?"#, in: text) {
            text = text.replacingCharacters(in: match.range, with: " ")
        }

        if let (date, range, hasTime) = detectDate(in: text, now: now, calendar: calendar) {
            result.day = calendar.startOfDay(for: date)
            if hasTime { result.due = date }
            text = text.replacingCharacters(in: range, with: " ")
        }

        // "every monday" without a date starts on the next Monday (or today if it is one).
        if result.day == nil, let repeatWeekday {
            let today = calendar.startOfDay(for: now)
            result.day = calendar.component(.weekday, from: today) == repeatWeekday
                ? today
                : RepeatRule.weekly([repeatWeekday]).next(after: today, calendar: calendar)
        }
        if case .weekly(let days) = result.repeatRule, days.isEmpty {
            let start = result.day ?? calendar.startOfDay(for: now)
            result.repeatRule = .weekly([calendar.component(.weekday, from: start)])
        }

        result.title = cleanTitle(text)
        if result.title.isEmpty { result.title = input.trimmingCharacters(in: .whitespacesAndNewlines) }
        return result
    }

    // MARK: - Pieces

    private static func priority(from token: String) -> TaskPriority? {
        switch token.lowercased() {
        case "!!!", "!high", "!h", "!1", "p1": .high
        case "!!", "!medium", "!med", "!m", "!2", "p2": .medium
        case "!", "!low", "!l", "!3", "p3": .low
        default: nil
        }
    }

    private static func weekdayIndex(_ name: String, calendar: Calendar) -> Int? {
        let english = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return english.firstIndex(of: name.lowercased()).map { $0 + 1 }
    }

    private static let timePattern = try! NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\d{1,2}:\d{2}|noon|midnight|tonight|morning|afternoon|evening)\b"#
    )
    private static let dayWordPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(today|tomorrow|tonight|yesterday|mon|tue|wed|thu|fri|sat|sun|week|month|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d{1,2}[/.-]\d{1,2})"#
    )

    private static func detectDate(in text: String, now: Date, calendar: Calendar) -> (Date, Range<String.Index>, Bool)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        guard let match = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              var date = match.date,
              let range = Range(match.range, in: text) else { return nil }
        let phrase = String(text[range])
        let whole = NSRange(location: 0, length: (phrase as NSString).length)
        let hasTime = timePattern.firstMatch(in: phrase, range: whole) != nil
        let hasDay = dayWordPattern.firstMatch(in: phrase, range: whole) != nil
        // "at 5pm" after 5pm means tomorrow.
        if hasTime, !hasDay, date < now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        // Absorb a preposition right before the phrase ("on Friday", "at 5pm", "by noon").
        var lower = range.lowerBound
        let before = text[..<lower]
        if let prep = before.range(of: #"(?i)\b(on|at|by|for|due)\s+$"#, options: .regularExpression) {
            lower = prep.lowerBound
        }
        return (date, lower..<range.upperBound, hasTime)
    }

    private static func cleanTitle(_ text: String) -> String {
        var title = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        title = title.replacingOccurrences(of: #"(?i)\s+(on|at|by|for|due|to)$"#, with: "", options: .regularExpression)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;-"))
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private struct Match {
        let range: Range<String.Index>
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(result.range, in: text) else { return nil }
        let groups = (1..<max(result.numberOfRanges, 1)).map { index -> String in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        return Match(range: range, groups: groups)
    }
}
