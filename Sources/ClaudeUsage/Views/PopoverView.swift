import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var usage: UsageTracker
    @EnvironmentObject var limits: PlanLimitClient
    @EnvironmentObject var recent: RecentSessionStore
    @State private var showSettings = false
    @AppStorage("popoverTab") private var tab = 0 // 0 = now, 1 = recent, 2 = usage
    @State private var range = 0 // 0 = today, 1 = week
    @State private var hoveredBar: Int?
    @State private var refreshTurns = 0.0
    @State private var greetingBounce = 0
    /// Measured height of the current tab's content; the popover shrinks to fit it.
    @State private var contentHeight: CGFloat = 300
    private let maxContentHeight: CGFloat = 470
    /// The menu bar window. It doesn't follow SwiftUI size changes by itself, so `fitWindow` resizes it.
    @State private var window: NSWindow?

    var body: some View {
        // Header and tabs pinned on top; the body is exactly as tall as its content (scrolling past a max),
        // so there is no empty space and nothing floats in the middle.
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                header
                if !showSettings {
                    PillToggle(options: ["Now", "Recent", "Usage"], selection: $tab, fill: true)
                }
            }
            .padding([.horizontal, .top], 14)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if showSettings {
                        SettingsView()
                    } else {
                        VStack(spacing: 12) {
                            switch tab {
                            case 1: recentCard
                            case 2: tokensCard
                            default:
                                limitsCard
                                sessionsCard
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom], 14)
                .padding(.top, 2) // room for card shadows
                .frame(maxWidth: .infinity, alignment: .top)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .frame(height: min(contentHeight, maxContentHeight))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
        .frame(width: 344)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PopoverHeightKey.self, value: geo.size.height)
        })
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
        .overlay { ConfettiView(trigger: sessions.finishCount) }
        .background(WindowReader { if window !== $0 { window = $0 } })
        .onPreferenceChange(PopoverHeightKey.self) { fitWindow(height: $0) }
        .onChange(of: window) { _, _ in fitWindow(height: popoverHeight) }
        .onAppear {
            usage.refresh()
            if tab == 1 { loadRecent() }
        }
        .onChange(of: tab) { _, t in if t == 1 { loadRecent() } }
    }

    @State private var popoverHeight: CGFloat = 0

    /// Resizes the window to the content, keeping its top edge under the menu bar.
    private func fitWindow(height: CGFloat) {
        popoverHeight = height
        guard let window, height > 0 else { return }
        var frame = window.frame
        let newHeight = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: frame.width, height: height)).height
        guard abs(newHeight - frame.height) > 0.5 else { return }
        frame.origin.y = frame.maxY - newHeight
        frame.size.height = newHeight
        window.setFrame(frame, display: true, animate: false)
    }

    private func loadRecent() {
        recent.load(excluding: Set(sessions.sessions.compactMap(\.sessionId)))
    }

    // MARK: Header

    private var header: some View {
        let greeting = Greeting.now
        return HStack(spacing: 10) {
            Button { greetingBounce += 1 } label: {
                Image(systemName: greeting.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: greetingBounce)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(LinearGradient(colors: [Palette.lime, Palette.purple],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(showSettings ? "Settings" : greeting.text)
                    .font(.rounded(17, .bold))
                    .foregroundStyle(Palette.text)
                Text(statusLine)
                    .font(.rounded(12))
                    .foregroundStyle(Palette.text2)
                    .contentTransition(.interpolate)
            }
            Spacer()
            if !showSettings {
                IconButton(systemName: "arrow.clockwise", help: "Refresh", rotation: refreshTurns) {
                    withAnimation(.spring(duration: 0.7, bounce: 0.3)) { refreshTurns += 360 }
                    usage.refresh()
                    if tab == 1 { loadRecent() }
                    Task { await limits.refresh() }
                }
            }
            IconButton(systemName: showSettings ? "xmark" : "gearshape.fill", help: "Settings") {
                showSettings.toggle()
            }
            IconButton(systemName: "power", help: "Quit") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 2)
    }

    private var statusLine: String {
        let busy = sessions.busyCount
        if sessions.sessions.isEmpty { return "All quiet. Nothing running." }
        if busy == 0 { return "All caught up" }
        return busy == 1 ? "1 session working…" : "\(busy) sessions working…"
    }

    // MARK: Limits

    private var limitsCard: some View {
        let session = limits.windows.first { $0.id == "five_hour" }
        let week = limits.windows.first { $0.id == "seven_day" }
        let extras = limits.windows.filter { !["five_hour", "seven_day"].contains($0.id) }

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Plan limits") {
                if let error = limits.error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.sun)
                        .help(error)
                }
            }
            if limits.windows.isEmpty {
                Text(limits.error ?? "Checking your limits…")
                    .font(.rounded(12))
                    .foregroundStyle(Palette.text2)
            } else {
                LimitBar(title: "Session", percent: session?.utilization,
                         subtitle: session?.resetsAt.map(formatReset) ?? "", base: Palette.purple)
                LimitBar(title: "Week", percent: week?.utilization,
                         subtitle: week?.resetsAt.map(formatReset) ?? "", base: Palette.lime)
                ForEach(extras) { w in
                    Chip(label: w.title, value: "\(Int(w.utilization.rounded()))%",
                         color: Palette.level(w.utilization, base: Palette.lime))
                }
            }
        }
        .card()
    }

    // MARK: Sessions

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Sessions") {
                if !sessions.sessions.isEmpty {
                    Text("\(sessions.sessions.count)")
                        .font(.rounded(11, .bold))
                        .foregroundStyle(Palette.purple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.purple.opacity(0.12)))
                }
            }
            if sessions.sessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(Palette.text3)
                        .symbolEffect(.pulse)
                    Text("Start `claude` in a terminal and it shows up here.")
                        .font(.rounded(12))
                        .foregroundStyle(Palette.text2)
                }
                .padding(.vertical, 4)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        ForEach(sessions.sessions) { session in
                            SessionRow(session: session, now: context.date)
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: Recent

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Pick up where you left off")
            if recent.items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.text3)
                    Text(recent.loaded ? "No past sessions yet." : "Looking for past sessions…")
                        .font(.rounded(12))
                        .foregroundStyle(Palette.text2)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(recent.items) { RecentRow(session: $0) }
                }
            }
        }
        .card()
    }

    // MARK: Tokens

    private var tokensCard: some View {
        let week = range == 1
        let summary = week ? usage.lastSevenDays : usage.today
        let values = week ? usage.weekByDay : usage.todayByHour
        let models = week ? usage.weekByModel : usage.todayByModel
        let hour = Calendar.current.component(.hour, from: Date())

        let bigNumber = hoveredBar.map { values.indices.contains($0) ? values[$0] : 0 } ?? summary.total
        let caption: String = {
            guard let i = hoveredBar else { return week ? "tokens this week" : "tokens today" }
            return week ? "on \(weekdayLabels[i])" : String(format: "at %02d:00", i)
        }()

        return VStack(alignment: .leading, spacing: 12) {
            CardTitle("Tokens") {
                PillToggle(options: ["Today", "Week"], selection: $range)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatTokens(bigNumber))
                    .font(.rounded(32, .bold))
                    .foregroundStyle(hoveredBar == nil ? Palette.text : Palette.purple)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: bigNumber)
                Text(caption)
                    .font(.rounded(12))
                    .foregroundStyle(Palette.text2)
            }

            InteractiveBars(
                values: values,
                labels: week ? weekdayLabels : ["00", "06", "12", "18"],
                current: week ? 6 : hour,
                future: week ? nil : hour + 1,
                hovered: $hoveredBar
            )
            .id(range) // regrow the bars when switching ranges

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Chip(label: "Output", value: formatTokens(summary.output), color: Palette.purple)
                    Chip(label: "Input", value: formatTokens(summary.input), color: Palette.lime)
                }
                GridRow {
                    Chip(label: "Cache", value: formatTokens(summary.cacheRead + summary.cacheWrite), color: Palette.sun)
                    Chip(label: "Replies", value: summary.messages.formatted(), color: Palette.coral)
                }
            }

            if !models.isEmpty {
                Text(modelLine(models))
                    .font(.rounded(11))
                    .foregroundStyle(Palette.text3)
            }
        }
        .card()
    }

    private func modelLine(_ models: [ModelUsage]) -> String {
        let total = max(models.reduce(0) { $0 + $1.summary.total }, 1)
        return models.prefix(3).map {
            "\(prettyModelName($0.model)) \(Int((Double($0.summary.total) / Double(total) * 100).rounded()))%"
        }.joined(separator: "  ·  ")
    }

    private var weekdayLabels: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { i in
            cal.date(byAdding: .day, value: i - 6, to: today)!.formatted(.dateTime.weekday(.abbreviated))
        }
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: LiveSession
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(session.isBusy ? Palette.purple.opacity(0.15) : Palette.lime.opacity(0.3))
                    .frame(width: 32, height: 32)
                if session.isBusy {
                    WorkingBadge(hovering: hovering)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Palette.limeInk)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.rounded(13, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.rounded(11))
                    .foregroundStyle(session.isBusy ? Palette.purple : Palette.text2)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.text3)
                .opacity(hovering ? 1 : 0)
                .offset(x: hovering ? 0 : -6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Palette.bg : .clear)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.25)) { hovering = h } }
        .onTapGesture { TerminalLauncher.focus(session) }
        .contextMenu {
            Button("Jump to session") { TerminalLauncher.focus(session) }
            Button("Show in Finder") { TerminalLauncher.revealInFinder(session) }
        }
        .animation(.spring(duration: 0.45, bounce: 0.55), value: session.isBusy)
        .help("Jump to this session · \(session.folder)")
    }

    private var detail: String {
        let elapsed = session.statusSince.map { formatClock(now.timeIntervalSince($0)) } ?? ""
        return session.isBusy ? "Working · \(elapsed)" : "Done · \(session.shortFolder)"
    }
}

private struct PopoverHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Hands back the NSWindow a SwiftUI view lives in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Recent row

struct RecentRow: View {
    let session: RecentSession
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hovering ? "play.fill" : "bubble.left.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? Palette.onLime : Palette.limeInk)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hovering ? Palette.lime : Palette.lime.opacity(0.3)))

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.rounded(13, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(session.shortFolder) · \(session.lastActive.formatted(.relative(presentation: .named)))")
                    .font(.rounded(11))
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Text("Resume")
                    .font(.rounded(11, .bold))
                    .foregroundStyle(Palette.purple)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Palette.bg : .clear)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(duration: 0.25)) { hovering = h } }
        .onTapGesture { TerminalLauncher.resume(sessionId: session.id, cwd: session.cwd) }
        .contextMenu {
            Button("Resume in Terminal") { TerminalLauncher.resume(sessionId: session.id, cwd: session.cwd) }
            if let cwd = session.cwd {
                Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
                Button("Copy resume command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("cd '\(cwd)' && claude --resume \(session.id)", forType: .string)
                }
            }
        }
        .help("Resume in a new Terminal window")
    }
}

// MARK: - Greeting

struct Greeting {
    let text: String
    let symbol: String
    let color: Color

    static var now: Greeting {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return Greeting(text: "Good morning", symbol: "sun.max.fill", color: Palette.limeInk)
        case 12..<17: return Greeting(text: "Good afternoon", symbol: "sun.haze.fill", color: Palette.limeInk)
        case 17..<21: return Greeting(text: "Good evening", symbol: "sunset.fill", color: Palette.purple)
        default: return Greeting(text: "Late night coding", symbol: "moon.stars.fill", color: Palette.purple)
        }
    }
}

// MARK: - Formatting

func formatTokens(_ n: Int) -> String {
    let d = Double(n)
    switch d {
    case 1_000_000_000...: return String(format: "%.2fB", d / 1_000_000_000)
    case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
    case 1_000...: return String(format: "%.1fK", d / 1_000)
    default: return "\(n)"
    }
}

/// 2:54, 15:03, 1:02:10
func formatClock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

func formatReset(_ date: Date) -> String {
    let s = date.timeIntervalSinceNow
    if s <= 0 { return "resetting now" }
    if s < 24 * 3600 {
        let h = Int(s) / 3600, m = Int(s) % 3600 / 60
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }
    return "resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}
