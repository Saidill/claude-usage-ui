import AppKit
import Combine
import SwiftUI

/// Panel that holds the popover. It can take key focus (for pickers) without being a regular window.
private final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The menu bar icon and the popover it opens.
/// Built on NSStatusItem rather than SwiftUI's MenuBarExtra: hiding and re-showing a MenuBarExtra
/// (when switching to the notch and back) left a dead duplicate icon that couldn't be clicked.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    /// Nil while hidden. Hiding removes the item completely: toggling `isVisible` leaves a stray window behind.
    private var item: NSStatusItem?
    private(set) var panel: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var monitors: [Any] = []

    var isOpen: Bool { panel?.isVisible == true }
    var statusButton: NSStatusBarButton? { item?.button }

    private override init() {
        super.init()
        let sessions = AppModels.sessions, limits = AppModels.limits
        sessions.objectWillChange.merge(with: limits.objectWillChange)
            .merge(with: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () })
            .receive(on: RunLoop.main) // objectWillChange fires before the change; read values after it
            .sink { [weak self] in self?.updateButton() }
            .store(in: &subscriptions)
    }

    /// Shows or hides the icon (it's hidden while the app lives in the notch).
    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(buttonClicked)
            item.button?.imagePosition = .imageLeading
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            self.item = item
            updateButton()
        } else if !visible, let item {
            close()
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    @objc private func buttonClicked() {
        isOpen ? close() : open()
    }

    // MARK: Icon

    private func updateButton() {
        guard let button = item?.button else { return }
        let sessions = AppModels.sessions, limits = AppModels.limits
        let busy = sessions.busyCount
        let mode = MenuBarMode(rawValue: UserDefaults.standard.string(forKey: Settings.menuBarModeKey) ?? "") ?? .tasks
        let suffix: String = switch mode {
        case .tasks: busy > 0 ? "\(busy)" : ""
        case .fiveHour: limits.fiveHourPercent.map { "\(Int($0.rounded()))%" } ?? ""
        }
        button.image = sessions.celebrating
            ? MenuBarIcon.done()
            : MenuBarIcon.ring(fraction: (limits.fiveHourPercent ?? 0) / 100, dot: busy > 0)
        let title = suffix.isEmpty ? "" : " " + suffix
        if button.title != title { button.title = title }
    }

    // MARK: Popover

    func open() {
        guard let button = item?.button, let buttonWindow = button.window else { return }
        let panel = self.panel ?? makePanel()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let width: CGFloat = 344
        var x = anchor.midX - width / 2
        if let visible = screen?.visibleFrame { x = min(max(x, visible.minX + 8), visible.maxX - width - 8) }
        // Keep the current height (the view resizes the window to fit its content); pin the top under the icon.
        let height = max(panel.frame.height, 200)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 6 - height, width: width, height: height), display: false)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        startMonitoring()
    }

    func close() {
        guard isOpen else { return }
        panel?.orderOut(nil)
        item?.button?.highlight(false)
        stopMonitoring()
    }

    private func makePanel() -> NSPanel {
        let panel = PopoverPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 400),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let root = PopoverView()
            .environmentObject(AppModels.sessions)
            .environmentObject(AppModels.usage)
            .environmentObject(AppModels.limits)
            .environmentObject(AppModels.recent)
            .environmentObject(DisplayModeController.shared)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [] // PopoverView sizes the window itself
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// Closes on a click anywhere outside the popover, or on Escape.
    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.close() }; return nil }
            return event
        }) { monitors.append(local) }
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
