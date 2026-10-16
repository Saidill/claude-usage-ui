import AppKit
import Combine
import SwiftUI

/// What the notch is showing. The SwiftUI view animates between these.
@MainActor
final class NotchModel: ObservableObject {
    enum State: Equatable { case closed, live, pop, expanded }

    @Published var expanded = false
    /// The session that just finished, while its pop is showing.
    @Published var popped: LiveSession?
    /// Size of the hardware notch on this screen.
    @Published var notch = CGSize(width: 185, height: 32)
    /// Height of the full app content, measured by the view, so the shape fits it exactly.
    @Published var contentHeight: CGFloat = 300

    func state(busy: Bool) -> State {
        if expanded { return .expanded }
        if popped != nil { return .pop }
        return busy ? .live : .closed
    }

    /// Outer size of the black shape (including the little flares at its top corners) in each state.
    func size(for state: State) -> CGSize {
        let flare = NotchShape.flare(for: state)
        switch state {
        case .closed: return CGSize(width: notch.width + flare * 2, height: notch.height)
        case .live: return CGSize(width: notch.width + 100 + flare * 2, height: notch.height)
        case .pop: return CGSize(width: 340 + flare * 2, height: notch.height + 70)
        case .expanded:
            return CGSize(width: 376 + flare * 2,
                          height: min(notch.height - 8 + contentHeight, NotchWindowController.windowSize.height))
        }
    }
}

/// Borderless panel that floats over the menu bar and can take clicks without activating the app.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the notch window: placement, hover to open, the "finished" pop, and click-through when closed.
@MainActor
final class NotchWindowController {
    static let shared = NotchWindowController()
    /// The window never resizes (that's what made things lag); the shape animates inside it.
    static let windowSize = CGSize(width: 420, height: 640)

    let model = NotchModel()
    private var panel: NotchPanel?
    var window: NSWindow? { panel }
    /// The self-test can't move the real pointer, so it keeps the notch open itself.
    var holdOpenForTesting = false
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var openTask: Task<Void, Never>?
    private var pointerTimer: Timer?
    /// When the pointer left the open panel; it closes once it has been away long enough.
    private var leftAt: Date?
    private var popTask: Task<Void, Never>?
    private var hovering = false

    private init() {}

    /// Shows the notch on `screen`, or hides it when nil.
    func show(on screen: NSScreen?) {
        guard let screen, let notch = screen.notchSize else {
            panel?.orderOut(nil)
            stopMonitoring()
            close()
            return
        }
        model.notch = notch
        let panel = self.panel ?? makePanel()
        let size = Self.windowSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        startMonitoring()
        updateClickThrough()
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true // so moves over the open panel reach the local monitor

        let root = NotchView(model: model)
            .environmentObject(AppModels.sessions)
            .environmentObject(AppModels.usage)
            .environmentObject(AppModels.limits)
            .environmentObject(AppModels.recent)
            .environmentObject(DisplayModeController.shared)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [] // keep the window a fixed size
        panel.contentView = host
        self.panel = panel

        // Pop down when a session finishes.
        AppModels.sessions.$finishCount.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.sessionFinished() }
        }.store(in: &subscriptions)
        model.$expanded.combineLatest(model.$popped).sink { [weak self] _ in
            Task { @MainActor in self?.updateClickThrough() }
        }.store(in: &subscriptions)
        return panel
    }

    // MARK: Pop

    private func sessionFinished() {
        guard panel?.isVisible == true, let session = AppModels.sessions.lastFinished, !model.expanded else { return }
        model.popped = session
        schedulePopHide()
    }

    private func schedulePopHide() {
        popTask?.cancel()
        popTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            // Stay open while the pointer is on it.
            if self.hovering { self.schedulePopHide() } else { self.model.popped = nil }
        }
    }

    /// Jump button on the pop.
    func jump(to session: LiveSession) {
        TerminalLauncher.focus(session)
        popTask?.cancel()
        model.popped = nil
    }

    /// Clicking the pop opens the full app.
    func expand() {
        popTask?.cancel()
        model.popped = nil
        open()
    }

    // MARK: Hover

    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Monitors call back on the main thread, so handle the event right away instead of queueing it.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.checkPointer() }
            return event
        }) { monitors.append(local) }
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// The area that counts as "on the notch" right now, in screen coordinates.
    func activeRect() -> NSRect {
        guard let panel else { return .zero }
        let state = model.state(busy: AppModels.sessions.busyCount > 0)
        let size = model.size(for: state)
        let rect = NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - size.height,
                          width: size.width, height: size.height)
        if state == .expanded {
            // Open: generous slack all round, so it doesn't snap shut at the edge while you use it.
            return rect.insetBy(dx: -20, dy: -20)
        }
        // Closed: just the notch, never below it, so reaching for browser tabs under the notch can't open it.
        // It does reach past the top of the screen: a pointer pushed against the top edge sits exactly on it,
        // and `contains` treats the edge as outside.
        return NSRect(x: rect.minX - 6, y: rect.minY, width: rect.width + 12, height: rect.height + 10)
    }

    /// Called on every mouse move while closed, and on a short timer while open
    /// (an open panel takes the mouse, and macOS doesn't always report moves inside it).
    private func checkPointer() {
        let inside = activeRect().contains(NSEvent.mouseLocation)
        if inside {
            leftAt = nil
            guard !hovering else { return }
            hovering = true
            guard !model.expanded, model.popped == nil else { return }
            // Open once the pointer has rested on the notch for a moment, so passing through doesn't open it,
            // and never while a button is held (dragging a tab or window along the top).
            openTask?.cancel()
            openTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self, self.hovering, NSEvent.pressedMouseButtons == 0 else { return }
                self.open()
            }
        } else {
            hovering = false
            openTask?.cancel()
            guard model.expanded, !holdOpenForTesting else { return }
            // Close only after the pointer has stayed away for a moment, so a small overshoot doesn't shut it.
            let now = Date()
            if let leftAt {
                if now.timeIntervalSince(leftAt) > 0.3 { close() }
            } else {
                leftAt = now
            }
        }
    }

    func open() {
        model.expanded = true
        leftAt = nil
        updateClickThrough()
        pointerTimer?.invalidate()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
    }

    func close() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        leftAt = nil
        model.expanded = false
    }

    /// Clicks pass through to whatever is under the window unless something is open.
    private func updateClickThrough() {
        panel?.ignoresMouseEvents = !(model.expanded || model.popped != nil)
    }
}
