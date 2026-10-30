import AppKit

/// Owns the notch panel, keeps it pinned to the notch screen and routes mouse
/// tracking so only the visible shape intercepts clicks.
@MainActor
final class NotchWindowController {
    /// Fixed panel size; the window never resizes, only the SwiftUI shape animates.
    /// Leaves room for the expanded shape plus its shadow.
    private static let panelSize = CGSize(width: 600, height: 240)

    private let viewModel: NotchViewModel
    private let panel: NotchPanel
    private var hoverTracker: HoverTracker?
    private var observers: [NSObjectProtocol] = []
    private var currentDisplay = UserDefaults.standard.display

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize))
        let hostingView = NotchHostingView(rootView: NotchRootView(viewModel: viewModel))
        // The panel frame is fixed; never let SwiftUI push size changes to the window
        // (that re-sizing ran an NSAnimationContext group on every frame).
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        layout()
        panel.orderFrontRegardless()

        hoverTracker = HoverTracker(viewModel: viewModel, panel: panel)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.currentDisplay != UserDefaults.standard.display else { return }
                self.currentDisplay = UserDefaults.standard.display
                self.layout()
            }
        })
    }

    private func layout() {
        guard let screen = ScreenLocator.preferredScreen(currentDisplay) else { return }
        viewModel.geometry = ScreenLocator.geometry(for: screen)

        let frame = screen.frame
        panel.setFrame(
            CGRect(
                x: frame.midX - Self.panelSize.width / 2,
                y: frame.maxY - Self.panelSize.height,
                width: Self.panelSize.width,
                height: Self.panelSize.height
            ),
            display: true
        )
    }
}
