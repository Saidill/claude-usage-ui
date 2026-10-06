import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var sessions = SessionMonitor()
    @StateObject private var usage = UsageTracker()
    @StateObject private var limits = PlanLimitClient()
    @AppStorage(Settings.menuBarModeKey) private var menuBarMode = MenuBarMode.tasks.rawValue

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(sessions)
                .environmentObject(usage)
                .environmentObject(limits)
        } label: {
            MenuBarLabel(sessions: sessions, limits: limits, animator: sessions.menuBarAnimator,
                         mode: MenuBarMode(rawValue: menuBarMode) ?? .tasks)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var sessions: SessionMonitor
    @ObservedObject var limits: PlanLimitClient
    @ObservedObject var animator: MenuBarAnimator
    let mode: MenuBarMode

    var body: some View {
        let busy = sessions.busyCount
        let suffix: String = switch mode {
        case .tasks: busy > 0 ? "\(busy)" : ""
        case .fiveHour: limits.fiveHourPercent.map { "\(Int($0.rounded()))%" } ?? ""
        }
        HStack(spacing: 4) {
            Image(nsImage: icon(busy: busy))
            if !suffix.isEmpty { Text(suffix).monospacedDigit() }
        }
    }

    private func icon(busy: Int) -> NSImage {
        if sessions.celebrating { return MenuBarIcon.done() }
        if busy > 0 { return MenuBarIcon.spinner(phase: animator.phase) }
        return MenuBarIcon.ring(fraction: (limits.fiveHourPercent ?? 0) / 100)
    }
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
}
