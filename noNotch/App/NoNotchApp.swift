import SwiftUI

@main
struct NoNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings are shown from our own window (see SettingsWindowController);
        // agent apps can't reliably open the SwiftUI Settings scene.
        Settings { EmptyView() }
    }
}
