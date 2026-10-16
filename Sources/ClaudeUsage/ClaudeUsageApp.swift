import SwiftUI

@main
struct ClaudeUsageApp: App {
    init() {
        // Black theme: keep window chrome, tooltips and system controls dark too.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        // The menu bar icon and the notch are AppKit windows, managed by the display mode.
        _ = DisplayModeController.shared
        SelfTest.startIfRequested()
    }

    var body: some Scene {
        // Everything lives in the menu bar icon or the notch; this app has no regular windows.
        SwiftUI.Settings { EmptyView() }
    }
}

/// One copy of each model, shared by the menu bar popover and the notch.
@MainActor
enum AppModels {
    static let sessions = SessionMonitor()
    static let usage = UsageTracker()
    static let limits = PlanLimitClient()
    static let recent = RecentSessionStore()
}

enum MenuBarMode: String, CaseIterable, Identifiable {
    case tasks, fiveHour
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: return "Working sessions"
        case .fiveHour: return "Session limit %"
        }
    }
}

enum Settings {
    static let soundKey = "soundName"
    static let notifyKey = "notificationsEnabled"
    static let soundEnabledKey = "soundEnabled"
    static let menuBarModeKey = "menuBarMode"
    static let limitAlertsKey = "limitAlertsEnabled"
    static let limitThresholdKey = "limitAlertThreshold"
    static let resetPingKey = "resetPingEnabled"
    static let displayModeKey = "displayMode"
}
