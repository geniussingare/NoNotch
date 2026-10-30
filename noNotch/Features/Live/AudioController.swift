import AudioToolbox
import CoreAudio
import Foundation

/// System output volume through CoreAudio's virtual main volume.
enum AudioController {
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static var volume: Double {
        get {
            guard let device = defaultOutputDevice() else { return 0 }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return Double(value)
        }
        set {
            guard let device = defaultOutputDevice() else { return }
            var value = Float32(min(max(newValue, 0), 1))
            var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            if newValue > 0, isMuted { isMuted = false }
        }
    }

    static var isMuted: Bool {
        get {
            guard let device = defaultOutputDevice() else { return false }
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = address(kAudioDevicePropertyMute)
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return value != 0
        }
        set {
            guard let device = defaultOutputDevice() else { return }
            var value = UInt32(newValue ? 1 : 0)
            var address = address(kAudioDevicePropertyMute)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}
