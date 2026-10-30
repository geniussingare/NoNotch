import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics

/// Intercepts volume and brightness keys with a CGEventTap, applies the change
/// ourselves and swallows the event so the system OSD never appears.
/// Requires Accessibility permission.
@MainActor
final class MediaKeyInterceptor {
    private enum Key {
        static let soundUp: Int32 = 0
        static let soundDown: Int32 = 1
        static let brightnessUp: Int32 = 2
        static let brightnessDown: Int32 = 3
        static let mute: Int32 = 7
        /// Brightness keys on some keyboards arrive as plain key-downs.
        static let brightnessUpKeyCode: Int64 = 144
        static let brightnessDownKeyCode: Int64 = 145
    }

    /// 16 steps like macOS; Shift+Option gives quarter steps.
    private static let step = 1.0 / 16

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onActivity: (LiveActivity) -> Void

    init(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        // Literal value of kAXTrustedCheckOptionPrompt (the global isn't concurrency-safe).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil, Self.isTrusted else { return tap != nil }

        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: systemDefined | keyDown,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { interceptor.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let fine = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
        let step = fine ? Self.step / 4 : Self.step

        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            switch code {
            case Key.brightnessUpKeyCode: changeBrightness(by: step)
            case Key.brightnessDownKeyCode: changeBrightness(by: -step)
            default: return Unmanaged.passUnretained(event)
            }
            return nil
        }

        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let isDown = ((data & 0xFF00) >> 8) == 0xA

        switch keyCode {
        case Key.soundUp, Key.soundDown, Key.mute:
            if isDown { changeVolume(keyCode: keyCode, step: step) }
        case Key.brightnessUp, Key.brightnessDown:
            guard BrightnessController.isAvailable else { return Unmanaged.passUnretained(event) }
            if isDown { changeBrightness(by: keyCode == Key.brightnessUp ? step : -step) }
        default:
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func changeVolume(keyCode: Int32, step: Double) {
        if keyCode == Key.mute {
            AudioController.isMuted.toggle()
        } else {
            let delta = keyCode == Key.soundUp ? step : -step
            AudioController.volume = ((AudioController.volume + delta) / step).rounded() * step
        }
        let muted = AudioController.isMuted
        onActivity(.hud(.volume(muted: muted), value: muted ? 0 : AudioController.volume))
    }

    private func changeBrightness(by delta: Double) {
        let step = abs(delta)
        BrightnessController.brightness = ((BrightnessController.brightness + delta) / step).rounded() * step
        onActivity(.hud(.brightness, value: BrightnessController.brightness))
    }
}
