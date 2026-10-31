import SwiftUI

/// Shared tokens for the "Quiet Island" design: black, calm, colour only where it informs.
enum Design {
    // Text tokens meet WCAG contrast on black: secondary ≈ 10:1, tertiary ≈ 5.6:1.
    static let secondaryText = Color.white.opacity(0.72)
    static let tertiaryText = Color.white.opacity(0.52)
    static let fill = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.12)

    /// Icon size scale; every glyph uses one of these.
    enum Icon {
        static let small: CGFloat = 11
        static let medium: CGFloat = 13
        static let large: CGFloat = 17
        static let hero: CGFloat = 21
    }

    /// Minimum pointer target for any control.
    static let minTarget: CGFloat = 28

    /// SF Pro for text.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// SF Pro Rounded, reserved for numbers (clock, times, percentages).
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Buttons

/// Squishy press with a soft hover halo.
struct PressableStyle: ButtonStyle {
    var haloSize: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, haloSize: haloSize)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        let haloSize: CGFloat?
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background {
                    if let haloSize {
                        Circle()
                            .fill(.white.opacity(hovering ? 0.12 : 0))
                            .frame(width: haloSize, height: haloSize)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.86 : (hovering ? 1.06 : 1))
                .animation(NotchViewModel.snappy, value: configuration.isPressed)
                .animation(NotchViewModel.snappy, value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = Design.Icon.medium
    var halo: CGFloat = 30
    var tint: Color = .white
    /// Spoken by VoiceOver and shown as a tooltip; derived from the symbol if omitted.
    var label: String? = nil
    let action: () -> Void

    private var spokenLabel: String {
        label ?? symbol.split(separator: ".").first.map { String($0).capitalized } ?? symbol
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                // The visible halo can be small; the hit area never is.
                .frame(width: max(halo, Design.minTarget), height: max(halo, Design.minTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(haloSize: halo))
        .accessibilityLabel(Text(spokenLabel))
        .help(spokenLabel)
    }
}

// MARK: - Liquid Glass

/// Liquid Glass on macOS 26+, a quiet fill elsewhere or when the user has
/// Reduce Transparency on. Glass is for controls; content stays on a plain layer.
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(shape.fill(tint ?? Design.fill))
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return glass.interactive(interactive)
    }
}

/// Groups glass pieces so neighbours blend and morph into each other (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Round Liquid Glass control: transport buttons, toggles.
struct GlassControl: View {
    let symbol: String
    let label: String
    var diameter: CGFloat = 32
    var iconSize: CGFloat = Design.Icon.medium
    /// Filled state (toggle on, primary action).
    var isOn = false
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .glassSurface(Circle(), tint: isOn ? tint.opacity(0.88) : nil, interactive: true)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(label)
    }
}

extension View {
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

// MARK: - Slider

/// Capsule slider that thickens on hover, iOS Control Center style.
struct NotchSlider: View {
    @Binding var value: Double
    var tint: Color = .white
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let height: CGFloat = hovering || dragging ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * value))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        value = min(max(drag.location.x / proxy.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .onHover { hovering = $0 }
            .animation(NotchViewModel.snappy, value: hovering || dragging)
        }
        .frame(height: 12)
    }
}

// MARK: - Marquee

/// Scrolls text horizontally when it doesn't fit; static otherwise.
///
/// Layout-wise it behaves like a one-line, truncating `Text`: it takes only the
/// width it's offered. The scrolling copy lives in an overlay, so a long title
/// can never push neighbouring views (artwork, controls) out of the panel.
struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color = .white

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: Bool { textWidth > containerWidth + 1 }

    var body: some View {
        // Invisible sizing copy: one line tall, fully compressible in width.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .fixedSize()
                        .background(GeometryReader { Color.clear.preference(key: WidthKey.self, value: $0.size.width) })
                        .offset(x: offset)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                        .onAppear { containerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in containerWidth = width }
                }
            }
            .clipped()
            .mask {
                LinearGradient(
                    stops: overflow
                        ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.04), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)]
                        : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .onPreferenceChange(WidthKey.self) { textWidth = $0 }
            .onChange(of: text) { restart() }
            .onChange(of: textWidth) { restart() }
            .onChange(of: containerWidth) { restart() }
    }

    private func restart() {
        withAnimation(.linear(duration: 0)) { offset = 0 }
        guard overflow else { return }
        let distance = textWidth - containerWidth + 24
        withAnimation(.linear(duration: Double(distance) / 28).delay(1.5).repeatForever(autoreverses: true)) {
            offset = -distance
        }
    }

    private struct WidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}

// MARK: - Dotted label

/// Status words in the wings (PAUSED, DONE, WELCOME BACK): tiny, wide-tracked, dot-matrix flavoured.
struct DottedLabel: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
            .mask {
                // Fine horizontal scanlines give the dot-matrix look.
                VStack(spacing: 0.8) {
                    ForEach(0..<8, id: \.self) { _ in Rectangle().frame(height: 1.4) }
                }
            }
    }
}

// MARK: - Formatting

enum Format {
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
