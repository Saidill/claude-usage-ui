import AppKit

/// Where the app lives: in the menu bar (good with an external monitor) or in the MacBook notch.
enum DisplayMode: String, CaseIterable, Identifiable {
    case auto, menuBar, notch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .menuBar: return "Menu bar"
        case .notch: return "Notch"
        }
    }
}

/// Picks the mode actually in use and switches live when screens come and go.
@MainActor
final class DisplayModeController: ObservableObject {
    static let shared = DisplayModeController()

    @Published var setting: DisplayMode {
        didSet {
            UserDefaults.standard.set(setting.rawValue, forKey: Settings.displayModeKey)
            update()
        }
    }
    /// True when the app is shown in the notch rather than the menu bar.
    @Published private(set) var isNotch = false
    /// The built-in screen with a notch, if there is one.
    @Published private(set) var notchScreen: NSScreen?

    private init() {
        setting = UserDefaults.standard.string(forKey: Settings.displayModeKey).flatMap(DisplayMode.init) ?? .auto
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        (isNotch, notchScreen) = Self.resolve(setting)
        // The notch window refers back to `shared`, so build it once this initializer has returned.
        DispatchQueue.main.async { self.update() }
    }

    /// Flips between the menu bar and the notch (the header button).
    func toggle() {
        setting = isNotch ? .menuBar : .notch
    }

    private func update() {
        let (notch, notched) = Self.resolve(setting)
        notchScreen = notched
        if notch != isNotch { isNotch = notch }
        StatusItemController.shared.setVisible(!notch)
        NotchWindowController.shared.show(on: notch ? notched : nil)
    }

    private static func resolve(_ setting: DisplayMode) -> (notch: Bool, screen: NSScreen?) {
        let notched = NSScreen.screens.first { $0.notchSize != nil }
        let notch: Bool = switch setting {
        case .menuBar: false
        case .notch: notched != nil
        // Notch while the laptop screen is the only one; menu bar once an external monitor is connected.
        case .auto: notched != nil && NSScreen.screens.count == 1
        }
        return (notch, notched)
    }
}

extension NSScreen {
    /// Size of the camera notch, or nil on screens without one.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: right.minX - left.maxX, height: safeAreaInsets.top)
    }
}
