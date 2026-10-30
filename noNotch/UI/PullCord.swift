import SwiftUI

/// Shown on screens without a notch (external displays): a small hanging cord
/// you pull down to open, like a light switch. It sways when the pointer arrives.
struct PullCord: View {
    let onPull: () -> Void

    @State private var stretch: CGFloat = 0
    @State private var hovering = false
    @State private var swayTrigger = 0

    private static let pullThreshold: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(hovering ? 0.55 : 0.32))
                .frame(width: 1.5, height: 7 + stretch)
            Capsule()
                .fill(.black)
                .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.5 : 0.28), lineWidth: 0.75))
                .frame(width: hovering ? 34 : 26, height: 8)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: swayTrigger) { content, angle in
            content.rotationEffect(.degrees(angle), anchor: .top)
        } keyframes: { _ in
            SpringKeyframe(7, duration: 0.18)
            SpringKeyframe(-5, duration: 0.25)
            SpringKeyframe(2.5, duration: 0.25)
            SpringKeyframe(0, duration: 0.4)
        }
        .frame(width: 60, height: 40, alignment: .top)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(NotchViewModel.snappy) { hovering = inside }
            if inside { swayTrigger += 1 }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    // Rubber-band: the cord resists the further you pull.
                    let pull = max(drag.translation.height, 0)
                    stretch = min(pull * 0.7, 26)
                }
                .onEnded { drag in
                    let pulled = drag.translation.height > Self.pullThreshold
                    let tapped = abs(drag.translation.height) < 3 && abs(drag.translation.width) < 3
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { stretch = 0 }
                    if pulled || tapped { onPull() }
                }
        )
        .help("Pull down to open noNotch")
    }
}
