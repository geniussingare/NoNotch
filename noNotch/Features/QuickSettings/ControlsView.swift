import SwiftUI

/// Toggles in one row, two slim sliders and quick actions beneath.
struct ControlsView: View {
    let controls: SystemControls
    let hudActive: Bool
    var openMirror: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            GlassGroup(spacing: 12) {
            HStack(spacing: 8) {
                if controls.wifiAvailable {
                    ToggleButton(symbol: controls.wifiOn ? "wifi" : "wifi.slash", title: "Wi‑Fi", isOn: controls.wifiOn, action: controls.toggleWiFi)
                }
                if controls.bluetoothAvailable {
                    ToggleButton(symbol: "dot.radiowaves.left.and.right", title: "Bluetooth", isOn: controls.bluetoothOn, action: controls.toggleBluetooth)
                }
                ToggleButton(symbol: "moon.fill", title: "Focus", isOn: controls.focusOn, action: controls.toggleFocus)
                ToggleButton(symbol: "circle.lefthalf.filled", title: "Dark Mode", isOn: controls.darkMode, action: controls.toggleDarkMode)
                ToggleButton(symbol: "cup.and.saucer.fill", title: "Keep Awake", isOn: controls.keepAwake, action: controls.toggleKeepAwake)
            }
            }

            VStack(spacing: 10) {
                SliderRow(symbol: volumeSymbol, value: Binding(get: { controls.volume }, set: controls.setVolume))
                if controls.brightnessAvailable {
                    SliderRow(symbol: "sun.max.fill", value: Binding(get: { controls.brightness }, set: controls.setBrightness))
                }
                HStack(spacing: 2) {
                    IconButton(symbol: "person.crop.square", size: 11, halo: 24, tint: Design.secondaryText, action: openMirror)
                        .help("Mirror")
                    IconButton(symbol: "camera.viewfinder", size: 11, halo: 24, tint: Design.secondaryText, action: controls.screenshot)
                        .help("Screenshot")
                    IconButton(symbol: "lock.fill", size: 11, halo: 24, tint: Design.secondaryText, action: controls.lockScreen)
                        .help("Lock Screen")
                    IconButton(symbol: "waveform.path.ecg", size: 11, halo: 24, tint: Design.secondaryText, action: controls.openActivityMonitor)
                        .help("Activity Monitor")
                    Spacer()
                    if !hudActive {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Design.tertiaryText)
                            .help("Grant Accessibility in Settings to show volume and brightness in the notch")
                    }
                }
            }
        }
        .onAppear(perform: controls.refresh)
    }

    private var volumeSymbol: String {
        switch controls.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct ToggleButton: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        GlassControl(symbol: symbol, label: title, diameter: 36, iconSize: Design.Icon.medium, isOn: isOn, action: action)
            .animation(NotchViewModel.snappy, value: isOn)
    }
}

private struct SliderRow: View {
    let symbol: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Design.secondaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            NotchSlider(value: $value)
        }
    }
}
