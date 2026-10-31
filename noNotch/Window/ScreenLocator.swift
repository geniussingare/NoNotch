import AppKit

/// Size and position of the (real or virtual) notch on a screen.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool
}

enum ScreenLocator {
    /// The notched built-in display (or the main screen, per Settings).
    static func preferredScreen(_ choice: DisplayChoice) -> NSScreen? {
        let main = NSScreen.screens.first // The screen with the menu bar.
        switch choice {
        case .notched: return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? main
        case .main: return main
        }
    }

    static func geometry(for screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // Scaled modes ("More Space") report fractional points; snap outward to whole pixels
            // so the island covers the cut-out with no hairline above or sliver below it.
            let scale = max(screen.backingScaleFactor, 1)
            let snap = { (value: CGFloat) in (value * scale).rounded(.up) / scale }
            let width = snap(right.minX - left.maxX)
            return NotchGeometry(
                screenFrame: screen.frame,
                notchSize: CGSize(width: width, height: snap(screen.safeAreaInsets.top)),
                hasNotch: true
            )
        }

        // No notch: draw a virtual pill the height of the menu bar.
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(
            screenFrame: screen.frame,
            notchSize: CGSize(width: 190, height: menuBarHeight),
            hasNotch: false
        )
    }
}
