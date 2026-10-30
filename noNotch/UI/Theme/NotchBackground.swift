import AppKit
import SwiftUI

/// Themed fill behind the island.
///
/// Collapsed, both themes are pure black so the shape is indistinguishable
/// from the hardware cut-out. Open, the Glass theme keeps a black strip the
/// height of the notch (so it still blends) and melts into Liquid Glass below,
/// which refracts whatever is behind the panel.
struct NotchBackground: View {
    let theme: NotchTheme
    /// Expanded or showing a notification banner.
    let isOpen: Bool
    let notchHeight: CGFloat
    let shape: NotchShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if theme == .glass, isOpen, !reduceTransparency {
            GeometryReader { proxy in
                let height = max(proxy.size.height, 1)
                let solid = min(notchHeight / height, 1)
                let fade = min((notchHeight + 16) / height, 1)
                ZStack {
                    glass
                    // Black strip over the hardware notch, melting into the glass.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: solid),
                            .init(color: .black.opacity(0), location: fade),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(shape)
                }
            }
            .overlay(shape.stroke(Design.hairline, lineWidth: 0.5))
        } else {
            shape.fill(.black)
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.32)), in: shape)
        } else {
            ZStack {
                VisualEffectBlur(material: .hudWindow)
                Color.black.opacity(0.55)
            }
            .clipShape(shape)
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
