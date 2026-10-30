import Foundation
import IOKit.ps
import Observation

/// Event-driven battery state via IOKit power-source notifications (no polling).
@MainActor
@Observable
final class BatteryMonitor {
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var hasBattery = false

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var onActivity: (LiveActivity) -> Void = { _ in }
    @ObservationIgnored private var lastAlertLevel = 100

    func start(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
        read(announce: false)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.read(announce: true) }
        }, context)?.takeRetainedValue() else { return }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func read(announce: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue

            let pluggedChanged = plugged != isPluggedIn
            hasBattery = true
            level = newLevel
            isCharging = charging
            isPluggedIn = plugged

            guard announce else {
                lastAlertLevel = newLevel
                return
            }
            if pluggedChanged {
                onActivity(.power(level: newLevel, charging: charging, pluggedIn: plugged))
            }
            if !plugged, [20, 10, 5].contains(where: { newLevel <= $0 && lastAlertLevel > $0 }) {
                onActivity(.lowBattery(level: newLevel))
            }
            lastAlertLevel = plugged ? 100 : newLevel
            return
        }
    }
}
