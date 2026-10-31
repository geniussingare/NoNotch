import AppKit
import Foundation

// nonotch-mcp: a Model Context Protocol server over stdio (newline-delimited JSON-RPC 2.0).
// Claude Code, the Claude app and Cursor launch it; it reads and writes noNotch's store.json
// directly, and asks the running app to drive the focus timer.

/// The helper lives at noNotch.app/Contents/Helpers/nonotch-mcp; report the app's version.
let version: String = {
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}()
let file = StoreFile.standard
setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - JSON-RPC plumbing

typealias JSON = [String: Any]

func send(_ message: JSON) {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
}

func reply(_ id: Any, _ result: JSON) { send(["jsonrpc": "2.0", "id": id, "result": result]) }
func fail(_ id: Any, _ code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

struct ToolError: Error { let message: String }

// MARK: - Formatting

let isoDay: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

let isoMinute: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return f
}()

func describe(_ task: TaskItem) -> JSON {
    var out: JSON = ["id": task.id.uuidString.lowercased(), "title": task.title, "done": task.isDone]
    if task.priority != .none { out["priority"] = task.priority.title.lowercased() }
    if let project = task.project { out["project"] = project }
    if let day = task.day { out["day"] = isoDay.string(from: day) }
    if let due = task.due { out["reminder"] = isoMinute.string(from: due) }
    if let rule = task.repeatRule { out["repeat"] = rule.title }
    if !task.notes.isEmpty { out["notes"] = task.notes }
    if !task.steps.isEmpty { out["steps"] = task.steps.map { ["title": $0.title, "done": $0.done] } }
    if let done = task.done { out["completed"] = isoMinute.string(from: done) }
    return out
}

func text(_ value: Any) -> JSON {
    let body: String
    if let string = value as? String {
        body = string
    } else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
        body = String(decoding: data, as: UTF8.self)
    } else {
        body = "\(value)"
    }
    return ["content": [["type": "text", "text": body]]]
}

// MARK: - Argument helpers

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        (self[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func double(_ key: String) -> Double? {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        return string(key).flatMap(Double.init)
    }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
}

/// Full id or a unique prefix of one (case-insensitive).
func resolve(_ raw: String?, in data: StoreData) throws -> UUID {
    guard let raw = raw?.lowercased(), !raw.isEmpty else { throw ToolError(message: "Missing task id.") }
    let matches = data.tasks.filter { $0.id.uuidString.lowercased().hasPrefix(raw) }
    guard let only = matches.first, matches.count == 1 else {
        throw ToolError(message: matches.isEmpty ? "No task with id \(raw). Call list_tasks first." : "Id \(raw) is ambiguous; use more characters.")
    }
    return only.id
}

func parseDay(_ value: String) throws -> Date? {
    let lower = value.lowercased()
    if lower == "none" || lower == "anytime" || lower.isEmpty { return nil }
    if lower == "today" { return Calendar.current.startOfDay(for: Date()) }
    if lower == "tomorrow" { return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) }
    guard let date = isoDay.date(from: value) else { throw ToolError(message: "day must be YYYY-MM-DD, today, tomorrow or none.") }
    return Calendar.current.startOfDay(for: date)
}

/// "HH:mm" on `day`, or a full "YYYY-MM-DDTHH:mm".
func parseReminder(_ value: String, day: Date?) throws -> Date? {
    if value.lowercased() == "none" || value.isEmpty { return nil }
    if let full = isoMinute.date(from: value) { return full }
    let parts = value.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
        throw ToolError(message: "reminder must be HH:mm, YYYY-MM-DDTHH:mm or none.")
    }
    let base = day ?? Calendar.current.startOfDay(for: Date())
    return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base)
}

func parsePriority(_ value: String) throws -> TaskPriority {
    guard let priority = TaskPriority(name: value) else { throw ToolError(message: "priority must be none, low, medium or high.") }
    return priority
}

// MARK: - Tools

struct Tool {
    let name: String
    let description: String
    let properties: JSON
    var required: [String] = []
    let run: (JSON) throws -> JSON

    var schema: JSON {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as JSON]
    }
}

func prop(_ type: String, _ description: String, enum values: [String]? = nil) -> JSON {
    var out: JSON = ["type": type, "description": description]
    if let values { out["enum"] = values }
    return out
}

/// Sends a timer command and waits briefly for the app to confirm via its snapshot.
func focusCommand(_ action: AppCommand.Action, _ extra: [String: String] = [:]) throws -> JSON {
    let sent = Date()
    AppCommand.post(action, extra)
    for _ in 0..<15 {
        Thread.sleep(forTimeInterval: 0.1)
        let data = file.load()
        if let timer = data.timer, timer.updated >= sent { return text(timerStatus(data)) }
        if data.timer == nil, action == .focusStop { return text("Focus stopped.") }
    }
    let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.ganeshsingare.noNotch" }
    if !running { throw ToolError(message: "noNotch isn't running. Open noNotch to use the focus timer.") }
    return text(timerStatus(file.load()))
}

func timerStatus(_ data: StoreData) -> JSON {
    guard let timer = data.timer else { return ["state": "idle"] }
    var seconds = timer.seconds
    if timer.running {
        let drift = Date().timeIntervalSince(timer.updated)
        seconds = timer.mode == .countdown ? max(seconds - drift, 0) : seconds + drift
    }
    var out: JSON = [
        "state": timer.running ? "running" : "paused",
        "phase": timer.phase,
        "mode": timer.mode.rawValue,
        timer.mode == .countdown ? "remaining_seconds" : "elapsed_seconds": Int(seconds),
    ]
    if let id = timer.taskID, let task = data.task(id) { out["task"] = describe(task) }
    return out
}

let tools: [Tool] = [
    Tool(
        name: "list_tasks",
        description: "List noNotch tasks. 'today' = open tasks for today (including anytime and overdue, which roll forward), 'upcoming' = open tasks planned for later days, 'completed' = recently finished.",
        properties: [
            "scope": prop("string", "Which tasks (default today).", enum: ["today", "upcoming", "completed", "all"]),
            "project": prop("string", "Only tasks in this project."),
        ]
    ) { args in
        let data = file.load()
        var tasks: [TaskItem]
        switch args.string("scope") ?? "today" {
        case "upcoming": tasks = data.upcomingTasks()
        case "completed": tasks = Array(data.completedTasks().prefix(50))
        case "all": tasks = data.tasks.sorted(by: StoreData.displayOrder)
        default: tasks = data.todayTasks()
        }
        if let project = args.string("project")?.replacingOccurrences(of: "#", with: "").lowercased(), !project.isEmpty {
            tasks = tasks.filter { $0.project?.lowercased() == project }
        }
        return text(tasks.isEmpty ? "No tasks." : tasks.map(describe) as Any)
    },
    Tool(
        name: "add_task",
        description: "Add a task. 'text' understands natural language like \"call mom tomorrow at 5pm every week #family !high\". Explicit fields override what the text implies.",
        properties: [
            "text": prop("string", "The task, optionally with date, time, repeat, #project and !priority."),
            "day": prop("string", "YYYY-MM-DD, today, tomorrow or none."),
            "reminder": prop("string", "HH:mm (on the task's day) or YYYY-MM-DDTHH:mm. The notch opens with a chime then."),
            "priority": prop("string", "Priority.", enum: ["none", "low", "medium", "high"]),
            "project": prop("string", "Project name."),
            "notes": prop("string", "Notes."),
            "steps": ["type": "array", "items": ["type": "string"], "description": "Checklist steps."] as JSON,
        ],
        required: ["text"]
    ) { args in
        guard let raw = args.string("text"), !raw.isEmpty else { throw ToolError(message: "text is required.") }
        var parsed = TaskParser.parse(raw)
        if let day = args.string("day") { parsed.day = try parseDay(day) }
        if let reminder = args.string("reminder") {
            parsed.due = try parseReminder(reminder, day: parsed.day)
            if let due = parsed.due, parsed.day == nil { parsed.day = Calendar.current.startOfDay(for: due) }
        }
        if let priority = args.string("priority") { parsed.priority = try parsePriority(priority) }
        if let project = args.string("project") { parsed.project = project.replacingOccurrences(of: "#", with: "") }
        let notes = args.string("notes") ?? ""
        let steps = (args["steps"] as? [String] ?? []).map { TaskStep(title: $0) }
        let (_, task) = file.update { data -> TaskItem in
            var task = data.add(parsed)
            if !notes.isEmpty || !steps.isEmpty {
                data.update(task.id) { $0.notes = notes; $0.steps = steps }
                task = data.task(task.id) ?? task
            }
            return task
        }
        return text(["added": describe(task)])
    },
    Tool(
        name: "update_task",
        description: "Change a task's fields. Use 'none' to clear day, reminder or project.",
        properties: [
            "id": prop("string", "Task id (or a unique prefix) from list_tasks."),
            "title": prop("string", "New title."),
            "day": prop("string", "YYYY-MM-DD, today, tomorrow or none."),
            "reminder": prop("string", "HH:mm, YYYY-MM-DDTHH:mm or none."),
            "priority": prop("string", "Priority.", enum: ["none", "low", "medium", "high"]),
            "project": prop("string", "Project name or none."),
            "notes": prop("string", "Replace the notes."),
            "add_steps": ["type": "array", "items": ["type": "string"], "description": "Steps to append."] as JSON,
        ],
        required: ["id"]
    ) { args in
        let day = try args.string("day").map(parseDay)
        let priority = try args.string("priority").map(parsePriority)
        let (data, id) = try file.update { data -> UUID in
            let id = try resolve(args.string("id"), in: data)
            let current = data.task(id)!
            let reminder = try args.string("reminder").map { try parseReminder($0, day: day ?? current.day) }
            data.update(id) { task in
                if let title = args.string("title"), !title.isEmpty { task.title = title }
                if let day { task.day = day }
                if let reminder { task.due = reminder; task.alertedDue = nil }
                if let priority { task.priority = priority }
                if let project = args.string("project") {
                    task.project = ["none", ""].contains(project.lowercased()) ? nil : project.replacingOccurrences(of: "#", with: "")
                }
                if let notes = args["notes"] as? String { task.notes = notes }
                for step in args["add_steps"] as? [String] ?? [] { task.steps.append(TaskStep(title: step)) }
            }
            return id
        }
        return text(["updated": describe(data.task(id)!)])
    },
    Tool(
        name: "complete_task",
        description: "Mark a task done (or not done). Completing a repeating task schedules its next occurrence.",
        properties: [
            "id": prop("string", "Task id or unique prefix."),
            "done": prop("boolean", "Default true; false reopens it."),
        ],
        required: ["id"]
    ) { args in
        let done = args.bool("done") ?? true
        let (data, id) = try file.update { data -> UUID in
            let id = try resolve(args.string("id"), in: data)
            data.setDone(id, done)
            return id
        }
        return text([done ? "completed" : "reopened": describe(data.task(id)!)])
    },
    Tool(
        name: "delete_task",
        description: "Delete a task permanently.",
        properties: ["id": prop("string", "Task id or unique prefix.")],
        required: ["id"]
    ) { args in
        let (_, title) = try file.update { data -> String in
            let id = try resolve(args.string("id"), in: data)
            let title = data.task(id)!.title
            data.delete(id)
            return title
        }
        return text("Deleted “\(title)”.")
    },
    Tool(
        name: "get_note",
        description: "Read the daily notepad page for a day (default today).",
        properties: ["day": prop("string", "YYYY-MM-DD or today.")]
    ) { args in
        let day = try args.string("day").flatMap(parseDay) ?? Date()
        let note = file.load().dailyNotes[StoreData.noteKey(for: day)] ?? ""
        return text(note.isEmpty ? "The notepad for \(isoDay.string(from: day)) is empty." : note)
    },
    Tool(
        name: "append_note",
        description: "Append lines to today's notepad page.",
        properties: ["text": prop("string", "Text to append.")],
        required: ["text"]
    ) { args in
        guard let addition = args["text"] as? String, !addition.isEmpty else { throw ToolError(message: "text is required.") }
        let key = StoreData.noteKey(for: Date())
        file.update { data in
            let current = data.dailyNotes[key] ?? ""
            data.dailyNotes[key] = current.isEmpty ? addition : current + (current.hasSuffix("\n") ? "" : "\n") + addition
        }
        return text("Added to today's notepad.")
    },
    Tool(
        name: "get_insights",
        description: "The last seven days: tasks completed and minutes focused per day, plus the most productive hour.",
        properties: [:]
    ) { _ in
        let stats = InsightStats(data: file.load())
        var out: JSON = [
            "summary": stats.summary,
            "tasks_done": stats.tasksDone,
            "focus_minutes": Int(stats.focusSeconds / 60),
            "days": stats.days.map { ["day": isoDay.string(from: $0.date), "tasks_done": $0.tasks, "focus_minutes": Int($0.focusMinutes)] as JSON },
        ]
        if let peak = stats.peakHour { out["peak_hour"] = String(format: "%02d:00", peak) }
        return text(out)
    },
    Tool(
        name: "focus_start",
        description: "Start a focus session in the notch (noNotch must be running). A countdown by default.",
        properties: [
            "minutes": prop("number", "Countdown length (default from settings)."),
            "task_id": prop("string", "Task to focus on (id or unique prefix)."),
            "mode": prop("string", "countdown or stopwatch.", enum: ["countdown", "stopwatch"]),
        ]
    ) { args in
        var extra: [String: String] = [:]
        if let minutes = args.double("minutes") {
            guard minutes > 0, minutes <= 600 else { throw ToolError(message: "minutes must be between 1 and 600.") }
            extra[AppCommand.Key.minutes] = String(minutes)
        }
        if let raw = args.string("task_id") { extra[AppCommand.Key.taskID] = try resolve(raw, in: file.load()).uuidString }
        if let mode = args.string("mode") { extra[AppCommand.Key.mode] = mode }
        return try focusCommand(.focusStart, extra)
    },
    Tool(name: "focus_pause", description: "Pause the focus timer.", properties: [:]) { _ in try focusCommand(.focusPause) },
    Tool(name: "focus_resume", description: "Resume a paused focus timer.", properties: [:]) { _ in try focusCommand(.focusResume) },
    Tool(name: "focus_add_five", description: "Add five minutes to the running countdown.", properties: [:]) { _ in try focusCommand(.focusAddFive) },
    Tool(name: "focus_stop", description: "Stop the focus timer and log the session.", properties: [:]) { _ in try focusCommand(.focusStop) },
    Tool(name: "focus_status", description: "Current focus timer state.", properties: [:]) { _ in text(timerStatus(file.load())) },
]

// MARK: - Main loop

let instructions = """
    noNotch is the user's Mac notch app for tasks, a daily notepad and a focus timer. \
    Use list_tasks before changing tasks so you have their ids. Dates are in the user's local time zone; \
    today is \(isoDay.string(from: Date())).
    """

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? JSON,
          let method = message["method"] as? String else { continue }
    let id = message["id"]
    let params = message["params"] as? JSON ?? [:]

    switch method {
    case "initialize":
        guard let id else { continue }
        reply(id, [
            "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "nonotch", "title": "noNotch", "version": version],
            "instructions": instructions,
        ])
    case "ping":
        if let id { reply(id, [:]) }
    case "tools/list":
        if let id { reply(id, ["tools": tools.map(\.schema)]) }
    case "tools/call":
        guard let id else { continue }
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? JSON ?? [:]
        guard let tool = tools.first(where: { $0.name == name }) else {
            fail(id, -32602, "Unknown tool: \(name)")
            continue
        }
        do {
            reply(id, try tool.run(args))
        } catch let error as ToolError {
            reply(id, ["content": [["type": "text", "text": error.message]], "isError": true])
        } catch {
            reply(id, ["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
        }
    default:
        // Notifications (no id) are ignored; unknown requests get an error.
        if let id { fail(id, -32601, "Method not found: \(method)") }
    }
}
