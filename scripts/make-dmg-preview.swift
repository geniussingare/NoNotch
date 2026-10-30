// Composites the DMG window as Finder shows it (background + icons + labels)
// for the website's install section.
// Usage: swift scripts/make-dmg-preview.swift <background.png> <app-icon.png> <output.png>
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
let background = NSImage(contentsOfFile: args[0])!
let appIcon = NSImage(contentsOfFile: args[1])!
let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
let size = NSSize(width: 920, height: 448) // content + title bar

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let window = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 12, yRadius: 12)
window.addClip()
background.draw(in: NSRect(x: 0, y: 0, width: 920, height: 420))
// Title bar.
NSColor(white: 0.93, alpha: 1).setFill()
NSRect(x: 0, y: 420, width: 920, height: 28).fill()
for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 14 + CGFloat(i) * 20, y: 428, width: 12, height: 12)).fill()
}
let title = NSAttributedString(string: "noNotch", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor(white: 0.25, alpha: 1)])
title.draw(at: NSPoint(x: (920 - title.size().width) / 2, y: 426))

func place(_ image: NSImage, label: String, centerX: CGFloat) {
    let top: CGFloat = 236 // Finder y from top of content
    let y = 420 - top
    image.draw(in: NSRect(x: centerX - 52, y: y - 52, width: 104, height: 104))
    let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.1, alpha: 1)])
    text.draw(at: NSPoint(x: centerX - text.size().width / 2, y: y - 52 - 20))
}
place(appIcon, label: "noNotch", centerX: 300)
place(folderIcon, label: "Applications", centerX: 620)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
