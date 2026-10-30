import Foundation
import IOBluetooth

/// Announces Bluetooth audio devices (AirPods, Beats, headphones) as they connect and disconnect.
@MainActor
final class BluetoothMonitor: NSObject {
    private let onActivity: (LiveActivity) -> Void
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [IOBluetoothUserNotification] = []
    /// IOBluetooth replays already-connected devices on registration; ignore that burst.
    private var startedAt = Date.distantFuture

    init(onActivity: @escaping (LiveActivity) -> Void) {
        self.onActivity = onActivity
    }

    func start() {
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    // IOBluetooth calls these on a CoreBluetooth background queue, so they are
    // nonisolated: read what we need from the device here, then hop to main.
    @objc nonisolated private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let disconnect = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        let info = Self.describe(device)
        nonisolated(unsafe) let token = disconnect
        Task { @MainActor in
            if let token { self.disconnectNotifications.append(token) }
            guard Date().timeIntervalSince(self.startedAt) > 2 else { return }
            self.onActivity(.bluetooth(name: info.name, symbol: info.symbol, connected: true))
        }
    }

    @objc nonisolated private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        let info = Self.describe(device)
        nonisolated(unsafe) let token = notification
        Task { @MainActor in
            self.disconnectNotifications.removeAll { $0 === token }
            self.onActivity(.bluetooth(name: info.name, symbol: info.symbol, connected: false))
        }
    }

    private nonisolated static func describe(_ device: IOBluetoothDevice) -> (name: String, symbol: String) {
        let name = device.name ?? "Bluetooth Device"
        return (name, symbol(for: device, name: name))
    }

    private nonisolated static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("keyboard") { return "keyboard" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        // Major device class 0x04 = audio/video.
        if device.deviceClassMajor == 0x04 { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }
}
