import CoreGraphics
import Foundation

/// Built-in display brightness through the private DisplayServices framework.
/// Loaded lazily with dlopen so a missing symbol just disables the feature.
enum BrightnessController {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols: @unchecked Sendable {
        let get: GetFn
        let set: SetFn
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return Symbols(get: unsafeBitCast(get, to: GetFn.self), set: unsafeBitCast(set, to: SetFn.self))
    }()

    static var isAvailable: Bool { symbols != nil }

    private static var builtinDisplay: CGDirectDisplayID {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    static var brightness: Double {
        get {
            var value: Float = 0
            _ = symbols?.get(builtinDisplay, &value)
            return Double(value)
        }
        set {
            _ = symbols?.set(builtinDisplay, Float(min(max(newValue, 0), 1)))
        }
    }
}
