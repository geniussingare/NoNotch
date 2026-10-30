import Foundation
import os

/// Streams now-playing info from the private MediaRemote framework through the
/// vendored mediaremote-adapter, which runs inside Apple-signed `/usr/bin/perl`
/// (the only reliable route since macOS 15.4 added entitlement checks).
final class MediaRemoteBridge: @unchecked Sendable {
    enum Event: Sendable {
        case update(NowPlayingInfo?)
        /// The adapter exited repeatedly; callers should fall back.
        case unavailable
        /// A control command was rejected by the adapter.
        case commandFailed(MediaCommand)
    }

    private static let log = Logger(subsystem: "com.ganeshsingare.noNotch", category: "media")

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    private let script: URL?
    private let framework: URL?
    private let onEvent: @Sendable (Event) -> Void
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var process: Process?
        var buffer = Data()
        var quickFailures = 0
        var stopped = false
    }

    init(onEvent: @escaping @Sendable (Event) -> Void) {
        script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
        framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
        self.onEvent = onEvent
    }

    var isAvailable: Bool { script != nil && framework != nil }

    func start() {
        guard isAvailable else {
            onEvent(.unavailable)
            return
        }
        lock.withLock { $0.stopped = false }
        killOrphanedStreams()
        launchStream()
    }

    func stop() {
        let process = lock.withLock { state -> Process? in
            state.stopped = true
            return state.process
        }
        process?.terminate()
    }

    func send(_ command: MediaCommand) {
        run(["send", String(command.rawValue)]) { [onEvent] ok in
            if !ok { onEvent(.commandFailed(command)) }
        }
    }

    func seek(to seconds: TimeInterval) {
        run(["seek", String(Int64(max(seconds, 0) * 1_000_000))]) { _ in }
    }

    /// One-shot read of the current state, delivered as an update.
    func refresh() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = arguments(["get", "--micros"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [onEvent] _ in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            onEvent(.update(json.flatMap(NowPlayingInfo.init(adapterPayload:))))
        }
        try? process.run()
    }

    // MARK: - Private

    private func arguments(_ command: [String]) -> [String] {
        guard let script, let framework else { return [] }
        return [script.path, framework.path] + command
    }

    /// Runs a one-shot adapter command and reports whether it succeeded.
    private func run(_ command: [String], completion: @escaping @Sendable (Bool) -> Void) {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = arguments(command)
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let label = command.joined(separator: " ")
        process.terminationHandler = { finished in
            let ok = finished.terminationStatus == 0
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if ok {
                Self.log.info("adapter \(label, privacy: .public): ok")
            } else {
                Self.log.error("adapter \(label, privacy: .public) failed (\(finished.terminationStatus)): \(message, privacy: .public)")
            }
            completion(ok)
        }
        do {
            try process.run()
        } catch {
            Self.log.error("adapter \(label, privacy: .public) could not launch: \(error.localizedDescription, privacy: .public)")
            completion(false)
        }
    }

    /// A crashed previous run can leave its perl stream alive; it never notices
    /// the closed pipe while nothing plays. Clear those before starting ours.
    private func killOrphanedStreams() {
        guard let script else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "\(script.path) .* stream"]
        try? process.run()
        process.waitUntilExit()
    }

    private func launchStream() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = arguments(["stream", "--micros", "--no-diff", "--debounce=60"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }

        let launchedAt = Date()
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.streamEnded(after: Date().timeIntervalSince(launchedAt))
        }

        do {
            try process.run()
            lock.withLock { $0.process = process }
        } catch {
            onEvent(.unavailable)
        }
    }

    private func streamEnded(after lifetime: TimeInterval) {
        let action = lock.withLock { state -> (restart: Bool, giveUp: Bool) in
            state.process = nil
            state.buffer.removeAll()
            if state.stopped { return (false, false) }
            state.quickFailures = lifetime < 5 ? state.quickFailures + 1 : 0
            return (state.quickFailures < 3, state.quickFailures >= 3)
        }
        if action.giveUp {
            onEvent(.unavailable)
        } else if action.restart {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in self?.launchStream() }
        }
    }

    private func consume(_ chunk: Data) {
        let lines = lock.withLock { state -> [Data] in
            state.buffer.append(chunk)
            var lines: [Data] = []
            while let newline = state.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(state.buffer[state.buffer.startIndex..<newline])
                state.buffer.removeSubrange(state.buffer.startIndex...newline)
            }
            return lines
        }
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            onEvent(.update(NowPlayingInfo(adapterPayload: payload)))
        }
    }
}
