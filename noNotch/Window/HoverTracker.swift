import AppKit

/// Watches the pointer globally and decides when the notch expands or collapses.
/// Also flips `ignoresMouseEvents` so clicks outside the visible shape fall through.
@MainActor
final class HoverTracker {
    private static let collapseDelay: Duration = .milliseconds(250)

    private let viewModel: NotchViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var pending: Task<Void, Never>?
    /// Auto-collapse only after the pointer has visited the expanded notch,
    /// so expanding from the menu, hotkey or a drop doesn't immediately close again.
    private var hasEnteredSinceExpand = false
    private var dragChangeCount = -1
    /// Accumulated horizontal trackpad travel for the current swipe gesture.
    private var swipeTravel: CGFloat = 0
    private var swipeConsumed = false

    init(viewModel: NotchViewModel, panel: NotchPanel) {
        self.viewModel = viewModel
        self.panel = panel

        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.pointerMoved(dragging: dragging) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.pointerMoved(dragging: dragging) }
            return event
        }) {
            monitors.append(local)
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let precise = event.hasPreciseScrollingDeltas
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let began = event.phase == .began
            let ended = event.phase == .ended || event.phase == .cancelled
            let handled = MainActor.assumeIsolated {
                self?.scrolled(precise: precise, dx: dx, dy: dy, began: began, ended: ended) ?? false
            }
            return handled ? nil : event
        }) {
            monitors.append(scroll)
        }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) {
            monitors.append(clicks)
        }
    }

    isolated deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private var hitRect: CGRect {
        let frame = viewModel.geometry.screenFrame
        let size = viewModel.shapeSize
        let rect = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        // A little slack makes the collapsed notch easy to hit and stops edge flicker when expanded.
        return rect.insetBy(dx: -6, dy: viewModel.isExpanded ? -10 : -4)
    }

    private func pointerMoved(dragging: Bool) {
        let inside = hitRect.contains(NSEvent.mouseLocation)
        // Only touch the window when something changes; these setters round-trip
        // to the window server and mouse-moved fires constantly.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if panel.allowsKey != viewModel.isExpanded { panel.allowsKey = viewModel.isExpanded }
        // Far from the notch with nothing pending: nothing to do.
        if !inside, !viewModel.isExpanded, !viewModel.isHovering, pending == nil { return }

        if dragging {
            handleDrag(inside: inside)
            return
        }

        if inside {
            if viewModel.isExpanded {
                hasEnteredSinceExpand = true
                cancelPending()
            } else if viewModel.showsPullCord {
                // The cord opens on pull or click, not on hover.
            } else if pending == nil {
                viewModel.setHovering(true)
                schedule(after: .seconds(UserDefaults.standard.hoverDelay)) { [weak self] in
                    self?.hasEnteredSinceExpand = true
                    self?.viewModel.expand()
                }
            }
        } else {
            viewModel.setHovering(false)
            if viewModel.isExpanded {
                if hasEnteredSinceExpand, pending == nil, !isEditingText {
                    schedule(after: Self.collapseDelay) { [weak self] in self?.collapse() }
                }
            } else {
                cancelPending()
            }
        }
    }

    /// Dragging files onto the notch opens the shelf so they can be dropped.
    private func handleDrag(inside: Bool) {
        guard inside, !viewModel.isExpanded else {
            if inside { cancelPending() }
            return
        }
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != dragChangeCount {
            dragChangeCount = pasteboard.changeCount
            guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
            hasEnteredSinceExpand = true
            viewModel.expand(to: .shelf)
        }
    }

    /// Two-finger horizontal swipe flips tabs. Shelf and Clipboard keep the
    /// gesture for their own horizontal scrolling.
    private func scrolled(precise: Bool, dx: CGFloat, dy: CGFloat, began: Bool, ended: Bool) -> Bool {
        guard viewModel.isExpanded, precise,
              viewModel.tab != .shelf, viewModel.tab != .clipboard
        else { return false }
        if began {
            swipeTravel = 0
            swipeConsumed = false
        }
        if ended {
            swipeTravel = 0
            return false
        }
        guard abs(dx) > abs(dy) else { return false }
        swipeTravel += dx
        if !swipeConsumed, abs(swipeTravel) > 40 {
            swipeConsumed = true
            viewModel.step(tab: swipeTravel < 0 ? 1 : -1)
        }
        return true
    }

    /// A text view inside the notch has keyboard focus (Notes).
    private var isEditingText: Bool {
        panel.isKeyWindow && panel.firstResponder is NSTextView
    }

    private func clickedOutside() {
        guard viewModel.isExpanded, !hitRect.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    private func collapse() {
        cancelPending()
        hasEnteredSinceExpand = false
        dragChangeCount = -1
        viewModel.collapse()
        panel.makeFirstResponder(nil)
        panel.allowsKey = false
    }

    private func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            action()
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
