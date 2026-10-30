import AppKit
import os
import SwiftUI

/// Single source of truth for what's playing, music or video, from any app.
@MainActor
@Observable
final class NowPlayingService {
    /// Apps whose sessions are almost always video.
    private static let videoPlayers: Set<String> = [
        "com.colliderli.iina", "org.videolan.vlc", "com.apple.QuickTimePlayerX", "com.apple.TV",
        "com.netflix.Netflix", "com.firecore.infuse", "com.movist.MovistPro", "com.apple.podcasts.video",
    ]
    private static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "app.zen-browser.zen", "com.apple.SafariTechnologyPreview",
    ]

    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    private(set) var artworkAspect: CGFloat = 1
    private(set) var palette = ArtworkPalette.fallback
    private(set) var sourceIcon: NSImage?
    private(set) var sourceName = ""
    private(set) var usingFallback = false
    /// The playing app is the frontmost app; like iOS, its live activity steps aside.
    private(set) var isSourceFrontmost = false
    let lyrics = LyricsService()

    @ObservationIgnored private var bridge: MediaRemoteBridge?
    @ObservationIgnored private var fallback: AppleScriptFallback?
    @ObservationIgnored private var lastArtworkData: Data?
    @ObservationIgnored private var lastSourceID = ""
    @ObservationIgnored private var frontmostObserver: NSObjectProtocol?

    var hasMedia: Bool { info != nil }
    var isPlaying: Bool { info?.isPlaying ?? false }

    /// Video if the app is a known player, MediaRemote says so, or a browser
    /// session has a widescreen thumbnail (YouTube, Netflix, Twitch...).
    var isVideo: Bool {
        guard let info else { return false }
        if Self.videoPlayers.contains(info.appBundleID) { return true }
        if info.mediaType?.localizedCaseInsensitiveContains("video") == true { return true }
        return Self.browsers.contains(info.appBundleID) && (artworkAspect > 1.25 || artwork == nil)
    }

    func start() {
        let bridge = MediaRemoteBridge { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.bridge = bridge
        bridge.start()

        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrontmost() }
        }
    }

    private func updateFrontmost() {
        var isFront = false
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let info {
            // Browsers and some players report a helper process (e.g. com.brave.Browser.helper).
            isFront = [info.appBundleID, info.bundleID].contains { $0 == front || $0.hasPrefix(front + ".") }
        }
        guard isFront != isSourceFrontmost else { return }
        withAnimation(NotchViewModel.spring) { isSourceFrontmost = isFront }
    }

    func stop() {
        bridge?.stop()
        fallback?.stop()
    }

    // MARK: Controls

    func togglePlayPause() {
        // Optimistic flip so the UI responds instantly; the stream confirms.
        if var info {
            info.elapsed = info.position(at: Date())
            info.timestamp = Date()
            info.isPlaying.toggle()
            withAnimation(NotchViewModel.spring) { self.info = info }
        }
        send(.togglePlayPause)
    }

    /// The play/pause icon flips optimistically; if no confirming update arrives,
    /// ask the adapter for the real state instead of leaving the UI wrong.
    private func restoreTruthfulState() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.bridge?.refresh()
        }
    }

    func next() { send(.next) }
    func previous() { send(.previous) }
    func skip(forward: Bool) { send(forward ? .forward15 : .back15) }

    func seek(to seconds: TimeInterval) {
        if var info {
            info.elapsed = seconds
            info.timestamp = Date()
            self.info = info
        }
        if usingFallback { fallback?.seek(to: seconds) } else { bridge?.seek(to: seconds) }
    }

    func openSourceApp() {
        guard let id = info?.appBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        else { return }
        app.activate()
    }

    private func send(_ command: MediaCommand) {
        Self.log.info("control: \(String(describing: command), privacy: .public)")
        if usingFallback {
            // AppleScript only reaches Music/Spotify; media keys reach every player.
            if !MediaKeys.post(command) { fallback?.send(command) }
        } else {
            bridge?.send(command)
        }
    }

    private static let log = Logger(subsystem: "com.ganeshsingare.noNotch", category: "media")

    #if DEBUG
    /// Test hook: feed a now-playing snapshot without the adapter.
    func inject(_ info: NowPlayingInfo?) { apply(info) }
    #endif

    // MARK: Updates

    private func handle(_ event: MediaRemoteBridge.Event) {
        switch event {
        case .update(let info):
            apply(info)
        case .commandFailed(let command):
            // MediaRemote refused the command; press the hardware media key instead.
            Self.log.error("falling back to media key for \(String(describing: command), privacy: .public)")
            if !MediaKeys.post(command) { fallback?.send(command) }
            restoreTruthfulState()
        case .unavailable:
            guard !usingFallback else { return }
            usingFallback = true
            let fallback = AppleScriptFallback { [weak self] in self?.apply($0) }
            self.fallback = fallback
            fallback.start()
        }
    }

    private func apply(_ newInfo: NowPlayingInfo?) {
        guard newInfo != info else { return }
        withAnimation(NotchViewModel.spring) { info = newInfo }
        updateFrontmost()
        lyrics.load(for: newInfo)

        if let id = newInfo?.appBundleID, id != lastSourceID {
            lastSourceID = id
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
                sourceName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            } else {
                sourceIcon = nil
                sourceName = ""
            }
        }

        let data = newInfo?.artworkData
        guard data != lastArtworkData else { return }
        lastArtworkData = data
        guard let data, let image = NSImage(data: data) else {
            withAnimation(NotchViewModel.spring) {
                artwork = nil
                palette = .fallback
            }
            return
        }
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        Task {
            let palette = await Task.detached(priority: .utility) { ArtworkPalette.extract(from: data) }.value
            guard data == self.lastArtworkData else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                self.artwork = image
                self.artworkAspect = aspect
                self.palette = palette
            }
        }
    }
}
