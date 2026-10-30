import Carbon.HIToolbox

/// ⌃⌥Space toggles the notch from anywhere (Carbon is still the only public
/// API for system-wide hotkeys without Accessibility).
@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler
        )

        let id = EventHotKeyID(signature: OSType(0x534E_4F54), id: 1) // 'SNOT'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}
