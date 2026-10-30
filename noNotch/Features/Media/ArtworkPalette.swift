import AppKit
import SwiftUI

/// Dominant colours pulled from album art / video thumbnails, used to tint
/// the notch glow, waveform and progress bar.
struct ArtworkPalette: Equatable, Sendable {
    var primary: RGB
    var secondary: RGB

    struct RGB: Equatable, Sendable {
        var r: Double, g: Double, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    static let fallback = ArtworkPalette(
        primary: RGB(r: 0.55, g: 0.45, b: 1.0),
        secondary: RGB(r: 0.2, g: 0.8, b: 0.95)
    )

    /// Downsamples to 24×24 and buckets pixels by hue, weighting saturated and
    /// mid-bright pixels so muddy backgrounds don't win.
    static func extract(from data: Data) -> ArtworkPalette {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 24,
              ] as CFDictionary)
        else { return .fallback }

        let size = 24
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .fallback }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, weight = 0.0 }
        var buckets = [Bucket](repeating: Bucket(), count: 12)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            let weight = saturation * saturation * (1 - abs(maxC - 0.65)) + 0.02
            let hue = Self.hue(r: r, g: g, b: b, maxC: maxC, minC: minC)
            let index = min(Int(hue * 12), 11)
            buckets[index].r += r * weight
            buckets[index].g += g * weight
            buckets[index].b += b * weight
            buckets[index].weight += weight
        }

        let ranked = buckets.enumerated()
            .filter { $0.element.weight > 0 }
            .sorted { $0.element.weight > $1.element.weight }
        guard let first = ranked.first else { return .fallback }
        // Prefer a second colour from a different part of the hue wheel.
        let second = ranked.dropFirst().first { abs($0.offset - first.offset) >= 2 } ?? ranked.dropFirst().first ?? first

        func color(_ bucket: Bucket) -> RGB {
            vivid(RGB(r: bucket.r / bucket.weight, g: bucket.g / bucket.weight, b: bucket.b / bucket.weight))
        }
        return ArtworkPalette(primary: color(first.element), secondary: color(second.element))
    }

    private static func hue(r: Double, g: Double, b: Double, maxC: Double, minC: Double) -> Double {
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        var h: Double
        if maxC == r { h = (g - b) / delta }
        else if maxC == g { h = (b - r) / delta + 2 }
        else { h = (r - g) / delta + 4 }
        h /= 6
        return h < 0 ? h + 1 : h
    }

    /// Lifts dark or washed-out colours so they glow on black.
    private static func vivid(_ c: RGB) -> RGB {
        let ns = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let out = NSColor(hue: h, saturation: min(max(s, 0.45), 0.9), brightness: max(b, 0.75), alpha: 1)
            .usingColorSpace(.sRGB) ?? .white
        return RGB(r: out.redComponent, g: out.greenComponent, b: out.blueComponent)
    }
}
