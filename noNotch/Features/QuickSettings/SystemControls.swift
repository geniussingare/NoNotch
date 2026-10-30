import AppKit
import CoreWLAN
import IOKit.pwr_mgt
import Observation

/// Quick-settings toggles. Private APIs are resolved lazily and each toggle
/// reports `nil` availability so the UI can hide what doesn't work.
@MainActor
@Observable
final class SystemControls {
    private(set) var wifiOn = false
    private(set) var bluetoothOn = false
    private(set) var darkMode = false
    private(set) var keepAwake = false
    private(set) var focusOn = false
    var volume = 0.0
    var brightness = 0.0

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var appearanceObserver: NSKeyValueObservation?

    var wifiAvailable: Bool { CWWiFiClient.shared().interface() != nil }
    var bluetoothAvailable: Bool { BluetoothPower.isAvailable }
    var brightnessAvailable: Bool { BrightnessController.isAvailable }

    init() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
    }

    /// Re-reads live system state; called whenever the Controls tab appears.
    func refresh() {
        wifiOn = CWWiFiClient.shared().interface()?.powerOn() ?? false
        bluetoothOn = BluetoothPower.isOn
        darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        volume = AudioController.isMuted ? 0 : AudioController.volume
        brightness = BrightnessController.brightness
    }

    func toggleWiFi() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        try? interface.setPower(!wifiOn)
        wifiOn = interface.powerOn()
    }

    func toggleBluetooth() {
        BluetoothPower.isOn = !bluetoothOn
        bluetoothOn.toggle()
    }

    func toggleDarkMode() {
        darkMode.toggle()
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(darkMode)"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertionID)
            keepAwake = false
        } else {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "noNotch Keep Awake" as CFString,
                &assertionID
            )
            keepAwake = result == kIOReturnSuccess
        }
    }

    /// macOS has no public Focus API; we run a user Shortcut (set up once in Settings).
    func toggleFocus() {
        let name = UserDefaults.standard.string(forKey: SettingsKey.focusShortcut) ?? SettingsDefaults.focusShortcut
        focusOn.toggle()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }

    func setVolume(_ value: Double) {
        volume = value
        AudioController.volume = value
    }

    func setBrightness(_ value: Double) {
        brightness = value
        BrightnessController.brightness = value
    }

    // MARK: One-shot actions

    func screenshot() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    }

    func lockScreen() {
        typealias LockFn = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(symbol, to: LockFn.self)()
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        }
    }

    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}

/// Private IOBluetooth power toggles.
enum BluetoothPower {
    private typealias GetFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32) -> Void

    private struct Symbols: @unchecked Sendable {
        let get: GetFn
        let set: SetFn
    }

    private static let symbols: Symbols? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let get = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState"),
              let set = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return nil }
        return Symbols(get: unsafeBitCast(get, to: GetFn.self), set: unsafeBitCast(set, to: SetFn.self))
    }()

    static var isAvailable: Bool { symbols != nil }

    static var isOn: Bool {
        get { symbols?.get() == 1 }
        set { symbols?.set(newValue ? 1 : 0) }
    }
}
