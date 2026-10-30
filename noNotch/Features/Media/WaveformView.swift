import AppKit
import SwiftUI

/// Music-like bars. MediaRemote doesn't expose audio levels, so each bar runs
/// its own looping keyframe animation. Core Animation's render server drives
/// them, so playback costs the app no per-frame work.
struct Waveform: NSViewRepresentable {
    let playing: Bool
    let palette: ArtworkPalette
    var bars = 5

    func makeNSView(context: Context) -> WaveformLayerView {
        WaveformLayerView(bars: bars)
    }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.update(playing: playing, palette: palette)
    }
}

final class WaveformLayerView: NSView {
    private let barLayers: [CALayer]
    private var playing: Bool?
    private var palette: ArtworkPalette?

    init(bars: Int) {
        barLayers = (0..<bars).map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        barLayers.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let count = CGFloat(barLayers.count)
        let width = bounds.width / (count * 2 - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * width * 2 + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    func update(playing: Bool, palette: ArtworkPalette) {
        if palette != self.palette {
            self.palette = palette
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            for (index, bar) in barLayers.enumerated() {
                let rgb = index.isMultiple(of: 2) ? palette.primary : palette.secondary
                bar.backgroundColor = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            }
            CATransaction.commit()
        }

        guard playing != self.playing else { return }
        self.playing = playing
        for bar in barLayers {
            if playing {
                let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
                animation.values = (0..<6).map { _ in Double.random(in: 0.25...1) }
                animation.duration = Double.random(in: 0.7...1.3)
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.calculationMode = .cubic
                bar.add(animation, forKey: "level")
                bar.transform = CATransform3DIdentity
            } else {
                bar.removeAnimation(forKey: "level")
                bar.transform = CATransform3DMakeScale(1, 0.2, 1)
            }
        }
    }
}
