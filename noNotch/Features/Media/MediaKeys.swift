import AppKit

/// Synthesises the keyboard's hardware media keys (⏯ ⏭ ⏮). macOS routes these
/// to whichever app owns Now Playing, so this works for any player.
/// Posting events needs Accessibility; without it this is a no-op.
enum MediaKeys {
    // NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
    private static let play: Int32 = 16
    private static let next: Int32 = 17
    private static let previous: Int32 = 18

    /// Returns false when the command has no media-key equivalent.
    @discardableResult
    static func post(_ command: MediaCommand) -> Bool {
        let key: Int32
        switch command {
        case .play, .pause, .togglePlayPause: key = play
        case .next: key = next
        case .previous: key = previous
        case .back15, .forward15: return false
        }
        press(key, down: true)
        press(key, down: false)
        return true
    }

    private static func press(_ key: Int32, down: Bool) {
        let state: Int32 = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (state << 8)),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
