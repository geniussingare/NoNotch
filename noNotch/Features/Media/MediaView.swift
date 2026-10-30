import AVKit
import SwiftUI

/// Now-playing panel. Artwork on the left; title, progress and controls stacked
/// beside it. Video sessions get a 16:9 thumbnail and ±15 s skips.
struct MediaView: View {
    let viewModel: NotchViewModel
    private var media: NowPlayingService { viewModel.services.media }

    var body: some View {
        if let info = media.info {
            HStack(alignment: .center, spacing: 14) {
                Artwork(media: media)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            MarqueeText(text: info.title, font: Design.text(14, .semibold))
                            LyricOrSubtitle(media: media, info: info, subtitle: subtitle(info))
                        }
                        Waveform(playing: media.isPlaying, palette: media.palette, bars: 4)
                            .frame(width: 18, height: 14)
                            .padding(.top, 2)
                    }
                    Scrubber(media: media, info: info)
                    TransportControls(media: media)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
            }
        } else {
            EmptyMediaView()
        }
    }

    private func subtitle(_ info: NowPlayingInfo) -> String {
        let text = [info.artist, info.album].filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? media.sourceName : text
    }
}

private struct Artwork: View {
    let media: NowPlayingService

    var body: some View {
        let size = media.isVideo ? CGSize(width: 132, height: 74) : CGSize(width: 88, height: 88)
        let radius: CGFloat = media.isVideo ? 10 : 14

        ZStack(alignment: .bottomLeading) {
            if let image = media.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
                    .overlay {
                        if let icon = media.sourceIcon {
                            Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                        } else {
                            Image(systemName: media.isVideo ? "play.rectangle.fill" : "music.note")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(Design.tertiaryText)
                        }
                    }
            }
            if media.isVideo {
                Text("VIDEO")
                    .font(.system(size: 7.5, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(5)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            // Source app badge, like iOS media notifications.
            if media.artwork != nil, let icon = media.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: 5, y: 5)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .scaleEffect(media.isPlaying ? 1 : 0.94)
        .animation(NotchViewModel.spring, value: media.isPlaying)
        .onTapGesture { media.openSourceApp() }
        .help("Open \(media.sourceName)")
    }
}

private struct Scrubber: View {
    let media: NowPlayingService
    let info: NowPlayingInfo
    @State private var scrubValue: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !info.isPlaying || scrubValue != nil)) { context in
            let duration = max(info.duration, 0)
            let position = scrubValue.map { $0 * duration } ?? info.position(at: context.date)
            HStack(spacing: 8) {
                if duration > 0 {
                    Text(Format.time(position))
                        .frame(width: 34, alignment: .leading)
                    NotchSlider(
                        value: Binding(get: { scrubValue ?? (position / duration) }, set: { scrubValue = $0 }),
                        tint: media.palette.primary.color,
                        onEditingChanged: { editing in
                            if !editing, let scrubValue {
                                media.seek(to: scrubValue * duration)
                                self.scrubValue = nil
                            }
                        }
                    )
                    Text("-" + Format.time(max(duration - position, 0)))
                        .frame(width: 38, alignment: .trailing)
                } else {
                    // Live streams report no duration.
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("LIVE")
                    Spacer()
                }
            }
            .font(Design.number(9.5, .medium))
            .foregroundStyle(Design.tertiaryText)
        }
    }
}

private struct TransportControls: View {
    let media: NowPlayingService

    var body: some View {
        HStack(spacing: 8) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 8) {
                    if media.isVideo {
                        GlassControl(symbol: "gobackward.15", label: "Back 15 seconds", diameter: 30, iconSize: Design.Icon.small) { media.skip(forward: false) }
                    }
                    GlassControl(symbol: "backward.fill", label: "Previous", diameter: 30, iconSize: Design.Icon.small, action: media.previous)
                    GlassControl(
                        symbol: media.isPlaying ? "pause.fill" : "play.fill",
                        label: media.isPlaying ? "Pause" : "Play",
                        diameter: 38,
                        iconSize: Design.Icon.large,
                        isOn: true,
                        action: media.togglePlayPause
                    )
                    GlassControl(symbol: "forward.fill", label: "Next", diameter: 30, iconSize: Design.Icon.small, action: media.next)
                    if media.isVideo {
                        GlassControl(symbol: "goforward.15", label: "Forward 15 seconds", diameter: 30, iconSize: Design.Icon.small) { media.skip(forward: true) }
                    }
                }
            }
            Spacer()
            AirPlayButton()
                .frame(width: 28, height: 28)
                .help("AirPlay")
                .accessibilityLabel("AirPlay")
        }
    }
}

private struct AirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white.withAlphaComponent(0.45), for: .normal)
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

private struct EmptyMediaView: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: Design.Icon.hero, weight: .medium))
                .foregroundStyle(Design.tertiaryText)
                .frame(width: 88, height: 88)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Design.fill))
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing playing")
                    .font(Design.text(14, .semibold))
                Text("Music, Spotify, YouTube, VLC and IINA show up here.")
                    .font(Design.text(11.5))
                    .foregroundStyle(Design.secondaryText)
                Button("Open Music") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                }
                .buttonStyle(PillButtonStyle(tint: Design.fill))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Shows the current lyric line when synced lyrics exist, otherwise artist · album.
private struct LyricOrSubtitle: View {
    let media: NowPlayingService
    let info: NowPlayingInfo
    let subtitle: String

    var body: some View {
        if media.lyrics.lines.isEmpty {
            MarqueeText(text: subtitle, font: Design.text(12), color: Design.secondaryText)
        } else {
            TimelineView(.animation(minimumInterval: 0.25, paused: !info.isPlaying)) { context in
                let line = media.lyrics.line(at: info.position(at: context.date)) ?? subtitle
                Text(line)
                    .font(Design.text(12, .medium))
                    .foregroundStyle(media.palette.primary.color)
                    .lineLimit(1)
                    .id(line)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(NotchViewModel.spring, value: line)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
        }
    }
}
