#if DEBUG
import AppKit

/// Visual test harness: `noNotch.app/Contents/MacOS/noNotch -demo <state>` opens
/// the notch in a fixed state with sample data so it can be screenshotted.
/// States: home, media, video, controls, notes, shelf, clipboard, calendar,
/// notifications, banner, hud, music. Quits after 20 seconds.
@MainActor
enum DemoMode {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demo"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run(_ state: String, viewModel: NotchViewModel) {
        let services = viewModel.services
        let isVideo = state == "video"
        services.media.inject(NowPlayingInfo(
            bundleID: isVideo ? "com.google.Chrome" : "com.apple.Music",
            title: isVideo ? "Tu Jo Mila FULL VIDEO Song - Atif Aslam Pritam | Bajrangi Bhaijaan" : "Midnight City",
            artist: isVideo ? "T-Series" : "M83",
            album: isVideo ? "" : "Hurry Up, We're Dreaming",
            duration: 243, elapsed: 61, isPlaying: true, artworkData: sampleArtwork(wide: isVideo)
        ))

        switch state {
        case "banner":
            let item = NotificationMirror.Item(
                appName: "Messages", title: "Maya", body: "Dinner at 8? I booked the place.",
                date: Date(), appURL: URL(fileURLWithPath: "/System/Applications/Messages.app")
            )
            services.activities.post(.notification(item))
        case "hud":
            services.activities.post(.hud(.volume(muted: false), value: 0.62))
        case "music":
            break // collapsed with media wings
        case "video":
            viewModel.expand(to: .media)
        default:
            if let tab = NotchTab(rawValue: state) { viewModel.expand(to: tab) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { NSApp.terminate(nil) }
    }

    private static func sampleArtwork(wide: Bool) -> Data? {
        let size = wide ? NSSize(width: 320, height: 180) : NSSize(width: 300, height: 300)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: wide
                ? [NSColor(red: 0.85, green: 0.35, blue: 0.2, alpha: 1), NSColor(red: 0.2, green: 0.1, blue: 0.3, alpha: 1)]
                : [NSColor(red: 0.95, green: 0.4, blue: 0.6, alpha: 1), NSColor(red: 0.25, green: 0.35, blue: 0.9, alpha: 1)]
            )?.draw(in: rect, angle: -45)
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
#endif
