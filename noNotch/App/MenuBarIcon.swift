import AppKit

/// The menu bar mark: a tiny Dynamic Island holding the app icon's gradient tile and live bars.
/// Drawn on demand so the outline follows light/dark menu bars; the colour stays on brand.
enum MenuBarIcon {
    enum State: Equatable {
        case idle
        /// Focus progress 0…1; paused timers draw muted.
        case focus(progress: Double, paused: Bool)
    }

    static let size = NSSize(width: 26, height: 16)

    static func image(_ state: State, alert: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(state, alert: alert, in: ctx)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "noNotch"
        return image
    }

    private static func draw(_ state: State, alert: Bool, in ctx: CGContext) {
        // Resolved per draw, so it matches the menu bar's current appearance.
        let ink = NSColor.labelColor.cgColor

        // Content inside the island is always on black, so it uses white, not the menu bar ink.
        let white = CGColor(gray: 1, alpha: 1)

        // The island: solid black like the real one, with a rim that reads on dark menu bars.
        let island = CGRect(x: 1.5, y: 2.5, width: 23, height: 11)
        let capsule = CGPath(roundedRect: island, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
        ctx.addPath(capsule)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.addPath(capsule)
        ctx.setStrokeColor(ink.copy(alpha: 0.45) ?? ink)
        ctx.setLineWidth(1)
        ctx.strokePath()
        // A faint top sheen gives it the glassy edge of the app icon.
        ctx.saveGState()
        ctx.addPath(capsule)
        ctx.clip()
        let sheen = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: island.maxY), end: CGPoint(x: 0, y: island.midY), options: [])
        ctx.restoreGState()

        let tile = CGRect(x: 4.5, y: 5, width: 6, height: 6)
        switch state {
        case .idle:
            // Album tile: pink → violet → blue, like the app icon.
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 1.8, cornerHeight: 1.8, transform: nil))
            ctx.clip()
            let art = CGGradient(colorsSpace: nil, colors: [rgb(0xF472B6), rgb(0x8B5CF6), rgb(0x3B82F6)] as CFArray, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(art, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
            ctx.restoreGState()
            drawBars(in: ctx, heights: [3, 5.5, 4])

        case .focus(let progress, let paused):
            // Progress ring where the tile sits; bars become a calm two-step "timer" glyph.
            let center = CGPoint(x: tile.midX, y: tile.midY)
            let tint = paused ? CGColor(gray: 1, alpha: 0.6) : rgb(0xFF9F0A)
            ctx.setLineWidth(1.6)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
            ctx.addArc(center: center, radius: 2.9, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
            ctx.setStrokeColor(tint)
            ctx.setLineCap(.round)
            let start = CGFloat.pi / 2
            ctx.addArc(center: center, radius: 2.9, startAngle: start, endAngle: start - .pi * 2 * CGFloat(max(min(progress, 1), 0.02)), clockwise: true)
            ctx.strokePath()
            drawBars(in: ctx, heights: paused ? [4, 4] : [3, 5.5, 4], tint: paused ? [white.copy(alpha: 0.6) ?? white] : nil)
        }

        if alert {
            // A small yellow dot riding the island's top-right edge, cut out from the rim.
            let dot = CGRect(x: 20, y: 10, width: 5.5, height: 5.5)
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: dot.insetBy(dx: -1, dy: -1))
            ctx.setBlendMode(.normal)
            ctx.setFillColor(rgb(0xFFD60A))
            ctx.fillEllipse(in: dot)
        }
    }

    /// Live bars on the right: cyan → lavender.
    private static func drawBars(in ctx: CGContext, heights: [CGFloat], tint: [CGColor]? = nil) {
        let width: CGFloat = 1.5, gap: CGFloat = 1.3
        var x: CGFloat = 13.5
        let colors = tint ?? [rgb(0x22D3EE), rgb(0xA78BFA)]
        let gradient = CGGradient(colorsSpace: nil, colors: (colors.count == 1 ? colors + colors : colors) as CFArray, locations: [0, 1])!
        ctx.saveGState()
        for height in heights {
            let bar = CGRect(x: x, y: 8 - height / 2, width: width, height: height)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
            x += width + gap
        }
        ctx.clip()
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 13.5, y: 4), end: CGPoint(x: x, y: 12), options: [])
        ctx.restoreGState()
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
