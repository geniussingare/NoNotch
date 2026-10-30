// Renders the DMG window background (920×420 pt, @2x). Finder on recent macOS
// won't size a window narrower than ~920 pt, so the art is drawn at that width.
// Usage: swift scripts/make-dmg-background.swift <output.png> [version]
//
// Layout contract with scripts/release.sh (Finder coordinates, from top-left):
//   window 920×420 · app icon centre (300, 236) · Applications centre (620, 236) · icon size 104
import AppKit

let args = CommandLine.arguments.dropFirst()
let path = args.first ?? "dmg-background.png" // writes <path> (@2x pixels) and <path>@1x
let version = args.dropFirst().first ?? ""

let size = NSSize(width: 920, height: 420)
let scale: CGFloat = 2
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor { NSColor(white: white, alpha: alpha) }
/// Finder's y axis runs top-down; Core Graphics runs bottom-up.
func flip(_ y: CGFloat) -> CGFloat { size.height - y }

// Background: light neutral canvas. Finder always draws icon labels in dark
// text over a custom background, so the canvas must be light to keep them legible.
NSGradient(colors: [gray(0.985), gray(0.94)])!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// Brand motif: the island hanging from the top edge, holding a track and live bars.
let island = NSRect(x: 460 - 92, y: flip(30), width: 184, height: 30)
let islandPath = NSBezierPath()
islandPath.move(to: NSPoint(x: island.minX - 8, y: island.maxY))
islandPath.curve(to: NSPoint(x: island.minX, y: island.maxY - 8),
                 controlPoint1: NSPoint(x: island.minX, y: island.maxY), controlPoint2: NSPoint(x: island.minX, y: island.maxY))
islandPath.line(to: NSPoint(x: island.minX, y: island.minY + 13))
islandPath.curve(to: NSPoint(x: island.minX + 13, y: island.minY),
                 controlPoint1: NSPoint(x: island.minX, y: island.minY), controlPoint2: NSPoint(x: island.minX, y: island.minY))
islandPath.line(to: NSPoint(x: island.maxX - 13, y: island.minY))
islandPath.curve(to: NSPoint(x: island.maxX, y: island.minY + 13),
                 controlPoint1: NSPoint(x: island.maxX, y: island.minY), controlPoint2: NSPoint(x: island.maxX, y: island.minY))
islandPath.line(to: NSPoint(x: island.maxX, y: island.maxY - 8))
islandPath.curve(to: NSPoint(x: island.maxX + 8, y: island.maxY),
                 controlPoint1: NSPoint(x: island.maxX, y: island.maxY), controlPoint2: NSPoint(x: island.maxX, y: island.maxY))
islandPath.close()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: gray(0, 0.25).cgColor)
gray(0).setFill()
islandPath.fill()
ctx.restoreGState()
gray(1, 0.08).setStroke()
islandPath.lineWidth = 0.75
islandPath.stroke()
// Album tile + bars inside the island.
NSColor(red: 0.9, green: 0.28, blue: 0.3, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: island.minX + 12, y: island.midY - 7, width: 14, height: 14), xRadius: 4, yRadius: 4).fill()
for (index, level) in [0.45, 0.85, 0.6, 1.0].enumerated() {
    let height = 12 * CGFloat(level)
    gray(1, 0.9).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: island.maxX - 34 + CGFloat(index) * 5.5, y: island.midY - height / 2, width: 2.6, height: height),
        xRadius: 1.3, yRadius: 1.3
    ).fill()
}

// Text helpers.
func centered(_ text: String, font: NSFont, color: NSColor, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let measured = string.size()
    string.draw(at: NSPoint(x: (size.width - measured.width) / 2, y: flip(top) - measured.height))
}

centered("Install noNotch", font: .systemFont(ofSize: 22, weight: .semibold), color: gray(0.1), top: 64)
centered("Drag the app onto the Applications folder.", font: .systemFont(ofSize: 13), color: gray(0.38), top: 96)

// Icon wells. Finder draws the icons on top of these.
let appCenter = NSPoint(x: 300, y: flip(236))
let appsCenter = NSPoint(x: 620, y: flip(236))
for center in [appCenter, appsCenter] {
    gray(0, 0.045).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 64, y: center.y - 60, width: 128, height: 128)).fill()
}
// The drop target gets a dashed ring.
let ring = NSBezierPath(ovalIn: NSRect(x: appsCenter.x - 64, y: appsCenter.y - 60, width: 128, height: 128))
ring.lineWidth = 1.5
ring.setLineDash([6, 6], count: 2, phase: 0)
gray(0, 0.28).setStroke()
ring.stroke()

// Arrow between the wells.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 394, y: appCenter.y + 4))
arrow.line(to: NSPoint(x: 530, y: appCenter.y + 4))
arrow.lineWidth = 2.5
arrow.lineCapStyle = .round
gray(0, 0.4).setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 520, y: appCenter.y + 13))
head.line(to: NSPoint(x: 532, y: appCenter.y + 4))
head.line(to: NSPoint(x: 520, y: appCenter.y - 5))
head.lineWidth = 2.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

// Footer: GeniusSoft™ wordmark, trademark line, version.
gray(0, 0.1).setFill()
NSRect(x: 48, y: 52, width: 824, height: 0.5).fill()
let mark = NSMutableAttributedString(
    string: "GeniusSoft",
    attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: gray(0.12)]
)
mark.append(NSAttributedString(
    string: "™",
    attributes: [.font: NSFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: gray(0.12), .baselineOffset: 5]
))
mark.draw(at: NSPoint(x: 48, y: 24))
let legal = NSAttributedString(
    string: "noNotch™ is a trademark of GeniusSoft." + (version.isEmpty ? "" : "   Version \(version)"),
    attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: gray(0.45)]
)
legal.draw(at: NSPoint(x: 872 - legal.size().width, y: 25))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
