import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = Services()
    private lazy var viewModel = NotchViewModel(services: services)
    private lazy var settingsWindow = SettingsWindowController(services: services)
    private var notchController: NotchWindowController?
    private var menuBar: MenuBarController?
    private var hotKey: GlobalHotKey?
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; don't start services, windows or prompts.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        services.start()
        handleTerminationSignal()
        viewModel.openSettings = { [weak self] in self?.settingsWindow.show() }
        notchController = NotchWindowController(viewModel: viewModel)
        menuBar = MenuBarController(
            onToggle: { [weak self] in self?.viewModel.toggle() },
            onSettings: { [weak self] in self?.settingsWindow.show() }
        )
        hotKey = GlobalHotKey { [weak self] in self?.viewModel.toggle() }

        #if DEBUG
        if let state = DemoMode.requested {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            DemoMode.run(state, viewModel: viewModel)
            return
        }
        #endif

        // First launch: ask for every permission up front, once.
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            settingsWindow.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
    }

    /// `pkill`/Xcode stop send SIGTERM; route it through a normal quit so the
    /// media adapter and event tap shut down instead of being orphaned.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSource = source
    }
}
