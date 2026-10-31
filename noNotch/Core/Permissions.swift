import AppKit
import AVFoundation
import CoreBluetooth
import CoreLocation
import EventKit
import Observation

/// Every permission noNotch uses, asked for together on first launch.
enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case calendar
    case location
    case camera
    case bluetooth
    case automation
    case downloads
    case reminders
    case microphone

    /// Optional permissions can be skipped; "Allow All" leaves them alone.
    var isOptional: Bool { self == .reminders || self == .microphone }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .calendar: "Calendar"
        case .location: "Location"
        case .camera: "Camera"
        case .bluetooth: "Bluetooth"
        case .automation: "Automation"
        case .downloads: "Downloads Folder"
        case .reminders: "Reminders"
        case .microphone: "Microphone & Speech"
        }
    }

    var reason: String {
        switch self {
        case .accessibility: "Volume & brightness in the notch, window snapping"
        case .calendar: "Your next meeting and a Join button"
        case .location: "Local weather"
        case .camera: "Quick mirror before calls"
        case .bluetooth: "AirPods and device connections"
        case .automation: "Music/Spotify control and dark mode"
        case .downloads: "Download progress"
        case .reminders: "Optional: sync tasks to iPhone and Apple Watch"
        case .microphone: "Optional: dictate tasks and notes, recognised on this Mac"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .calendar: "calendar"
        case .location: "location.fill"
        case .camera: "camera.fill"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .automation: "gearshape.2.fill"
        case .downloads: "arrow.down.circle.fill"
        case .reminders: "checklist"
        case .microphone: "mic.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .accessibility: .systemBlue
        case .calendar: .systemRed
        case .location: .systemBlue
        case .camera: .systemGray
        case .bluetooth: .systemBlue
        case .automation: .systemGray
        case .downloads: .systemTeal
        case .reminders: .systemOrange
        case .microphone: .systemRed
        }
    }
}

@MainActor
@Observable
final class Permissions: NSObject {
    static let shared = Permissions()

    private(set) var granted: Set<PermissionKind> = []

    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var bluetooth: CBCentralManager?
    @ObservationIgnored private var automationChecked = false
    @ObservationIgnored private var automationGranted = false

    override private init() {
        super.init()
        location.delegate = self
        refresh()
    }

    var allGranted: Bool { PermissionKind.allCases.allSatisfy { $0.isOptional || granted.contains($0) } }

    func isGranted(_ kind: PermissionKind) -> Bool { granted.contains(kind) }

    func refresh() {
        var result: Set<PermissionKind> = []
        if AXIsProcessTrusted() { result.insert(.accessibility) }
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { result.insert(.calendar) }
        if [.authorizedAlways, .authorized].contains(location.authorizationStatus) { result.insert(.location) }
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { result.insert(.camera) }
        if CBManager.authorization == .allowedAlways { result.insert(.bluetooth) }
        if automationGranted { result.insert(.automation) }
        if Self.canReadDownloads { result.insert(.downloads) }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { result.insert(.reminders) }
        if Dictation.isAuthorized { result.insert(.microphone) }
        granted = result
    }

    /// Asks for one permission; the system shows its own prompt where one exists.
    func request(_ kind: PermissionKind) async {
        switch kind {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .location:
            location.requestWhenInUseAuthorization()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .bluetooth:
            bluetooth = CBCentralManager(delegate: nil, queue: nil)
        case .automation:
            automationGranted = await Self.requestAutomation()
        case .downloads:
            _ = Self.canReadDownloads
        case .reminders:
            _ = try? await EKEventStore().requestFullAccessToReminders()
        case .microphone:
            _ = await Dictation.authorize()
        }
        refresh()
    }

    /// Walks every missing permission in order, waiting for each prompt.
    func requestAll() async {
        for kind in PermissionKind.allCases where !isGranted(kind) && !kind.isOptional {
            await request(kind)
            // Give each system prompt a moment so they don't stack.
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    func openSettings(for kind: PermissionKind) {
        let pane = switch kind {
        case .accessibility: "Privacy_Accessibility"
        case .calendar: "Privacy_Calendars"
        case .location: "Privacy_LocationServices"
        case .camera: "Privacy_Camera"
        case .bluetooth: "Privacy_Bluetooth"
        case .automation: "Privacy_Automation"
        case .downloads: "Privacy_FilesAndFolders"
        case .reminders: "Privacy_Reminders"
        case .microphone: "Privacy_Microphone"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private static var canReadDownloads: Bool {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// Asks once to control System Events (covers dark mode; Music/Spotify are asked on first use).
    private static func requestAutomation() async -> Bool {
        // Running a harmless script triggers the system's Automation prompt.
        var error: NSDictionary?
        _ = NSAppleScript(source: "tell application \"System Events\" to return name of current user")?
            .executeAndReturnError(&error)
        return error == nil
    }
}

extension Permissions: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}
