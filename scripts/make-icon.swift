// Renders the noNotch app icon and website logo.
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let canvas: CGFloat = 1024

func render(size: CGFloat, background: Bool, draw: (CGContext, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / canvas, y: size / canvas)
    draw(ctx, canvas)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// The mark: a Dynamic-Island capsule holding an album tile and live bars,
/// with the content's colour spilling out below it.
func drawMark(_ ctx: CGContext, center: CGPoint, width: CGFloat) {
    let height = width * 0.30
    let island = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    let pill = CGPath(roundedRect: island, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)

    // Aura spilling out beneath the island.
    ctx.saveGState()
    let glowCenter = CGPoint(x: center.x, y: center.y - height * 0.9)
    let aura = CGGradient(
        colorsSpace: nil,
        colors: [color(0x8B5CF6, 0.55), color(0x3B82F6, 0.22), color(0x22D3EE, 0)] as CFArray,
        locations: [0, 0.45, 1]
    )!
    ctx.translateBy(x: glowCenter.x, y: glowCenter.y)
    ctx.scaleBy(x: 1.35, y: 0.75)
    ctx.drawRadialGradient(aura, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: width * 0.5, options: [])
    ctx.restoreGState()

    // Island body with a soft drop shadow and a hairline rim.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.12), blur: height * 0.5, color: color(0x000000, 0.6))
    ctx.addPath(pill)
    ctx.setFillColor(color(0x000000))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(pill)
    ctx.setLineWidth(height * 0.025)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.strokePath()
    ctx.restoreGState()

    // Album tile on the left.
    let tileSize = height * 0.62
    let tile = CGRect(x: island.minX + height * 0.19, y: center.y - tileSize / 2, width: tileSize, height: tileSize)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: tileSize * 0.28, cornerHeight: tileSize * 0.28, transform: nil))
    ctx.clip()
    let art = CGGradient(colorsSpace: nil, colors: [color(0xF472B6), color(0x8B5CF6), color(0x3B82F6)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(art, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()

    // Live bars on the right.
    let barWidth = height * 0.085
    let gap = height * 0.07
    let levels: [CGFloat] = [0.38, 0.72, 0.5, 0.86]
    let barsRight = island.maxX - height * 0.26
    let bars = CGGradient(colorsSpace: nil, colors: [color(0x22D3EE), color(0xA78BFA)] as CFArray, locations: [0, 1])!
    for (index, level) in levels.enumerated() {
        let barHeight = height * 0.62 * level
        let x = barsRight - CGFloat(levels.count - index) * (barWidth + gap) + gap
        let rect = CGRect(x: x, y: center.y - barHeight / 2, width: barWidth, height: barHeight)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(bars, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        ctx.restoreGState()
    }
}

// App icon: macOS grid (824pt squircle centred in 1024 with shadow).
let icon = render(size: 1024, background: true) { ctx, size in
    let inset: CGFloat = 100
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x0B0B12))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [color(0x14121F), color(0x050508)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Top "menu bar" sheen the island hangs from.
    let sheen = CGGradient(colorsSpace: nil, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.maxY - 220), options: [])
    // Ghost of the hardware notch the island has left behind: "no notch".
    let notchWidth: CGFloat = 300, notchHeight: CGFloat = 70
    let notch = CGMutablePath()
    let left = size / 2 - notchWidth / 2, right = size / 2 + notchWidth / 2, top = body.maxY
    notch.move(to: CGPoint(x: left, y: top))
    notch.addLine(to: CGPoint(x: left, y: top - notchHeight + 28))
    notch.addQuadCurve(to: CGPoint(x: left + 28, y: top - notchHeight), control: CGPoint(x: left, y: top - notchHeight))
    notch.addLine(to: CGPoint(x: right - 28, y: top - notchHeight))
    notch.addQuadCurve(to: CGPoint(x: right, y: top - notchHeight + 28), control: CGPoint(x: right, y: top - notchHeight))
    notch.addLine(to: CGPoint(x: right, y: top))
    ctx.saveGState()
    ctx.addPath(notch)
    ctx.setLineWidth(5)
    ctx.setLineDash(phase: 0, lengths: [16, 12])
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF, 0.28))
    ctx.strokePath()
    ctx.restoreGState()

    drawMark(ctx, center: CGPoint(x: size / 2, y: size * 0.6), width: 640)
    ctx.restoreGState()

    // Inner hairline.
    ctx.addPath(squircle)
    ctx.setLineWidth(2)
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.strokePath()
}
try! icon.write(to: output.appendingPathComponent("icon_1024.png"))

// Transparent mark for the website/logo.
let mark = render(size: 1024, background: false) { ctx, size in
    drawMark(ctx, center: CGPoint(x: size / 2, y: size / 2), width: 900)
}
try! mark.write(to: output.appendingPathComponent("mark.png"))
print("Wrote icon_1024.png and mark.png to \(output.path)")
