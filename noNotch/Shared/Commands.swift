import Foundation

/// Focus-timer commands the MCP helper sends to the running app via distributed notifications.
enum AppCommand {
    static let name = Notification.Name("com.ganeshsingare.noNotch.command")

    enum Action: String, Sendable {
        case focusStart, focusPause, focusResume, focusStop, focusAddFive
    }

    /// Keys in `userInfo`. Values are strings so they cross process boundaries untouched.
    enum Key {
        static let action = "action"
        static let minutes = "minutes"
        static let taskID = "taskID"
        static let mode = "mode"
    }

    static func post(_ action: Action, _ extra: [String: String] = [:]) {
        var info = extra
        info[Key.action] = action.rawValue
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }
}
