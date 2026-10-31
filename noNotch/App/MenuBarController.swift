import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onToggle: () -> Void
    private let onSettings: () -> Void

    init(onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onSettings = onSettings
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "noNotch")

        let menu = NSMenu()
        menu.addItem(item("About noNotch", #selector(about), key: ""))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates), key: ""))
        menu.addItem(.separator())
        menu.addItem(item("Toggle Notch", #selector(toggle), key: ""))
        menu.addItem(item("Settings…", #selector(settings), key: ","))
        menu.addItem(item("Report a Bug…", #selector(reportBug), key: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit noNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggle() { onToggle() }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "noNotch™",
            .credits: NSAttributedString(
                string: "A GeniusSoft™ product.\nNow Playing uses mediaremote-adapter (BSD-3-Clause).",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
    @objc private func settings() { onSettings() }
    @objc private func checkForUpdates() { UpdateChecker.shared.checkInteractively() }
    @objc private func reportBug() { UpdateChecker.shared.reportBug() }
}
