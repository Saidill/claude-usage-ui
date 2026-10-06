import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var usage: UsageTracker
    @EnvironmentObject var limits: PlanLimitClient
    @State private var showSettings = false
    @State private var range = 0 // 0 = today, 1 = week
    @State private var hoveredBar: Int?
    @State private var refreshTurns = 0.0
    @State private var greetingBounce = 0

    var body: some View {
        VStack(spacing: 12) {
            header
            if showSettings {
                SettingsView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 12) {
                    limitsCard
                    sessionsCard
                    tokensCard
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(width: 344)
        .background(Palette.bg)
        .overlay { ConfettiView(trigger: sessions.finishCount) }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: showSettings)
    }

    // MARK: Header

    private var header: some View {
        let greeting = Greeting.now
        return HStack(spacing: 10) {
            Button { greetingBounce += 1 } label: {
                Image(systemName: greeting.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(greeting.color)
                    .symbolEffect(.bounce, value: greetingBounce)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(greeting.color.opacity(0.16)))
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

        return VStack(alignment: .leading, spacing: 14) {
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
                HStack(spacing: 0) {
                    LiquidBubble(percent: session?.utilization, title: "Session",
                                 subtitle: session?.resetsAt.map(formatReset) ?? " ", base: Palette.blue)
                        .frame(maxWidth: .infinity)
                    LiquidBubble(percent: week?.utilization, title: "Week",
                                 subtitle: week?.resetsAt.map(formatReset) ?? " ", base: Palette.mint)
                        .frame(maxWidth: .infinity)
                }
                ForEach(extras) { w in
                    Chip(label: w.title, value: "\(Int(w.utilization.rounded()))%",
                         color: Palette.level(w.utilization, base: Palette.mint))
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
                        .foregroundStyle(Palette.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.blue.opacity(0.12)))
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
                    .foregroundStyle(hoveredBar == nil ? Palette.text : Palette.coral)
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
                    Chip(label: "Output", value: formatTokens(summary.output), color: Palette.coral)
                    Chip(label: "Input", value: formatTokens(summary.input), color: Palette.blue)
                }
                GridRow {
                    Chip(label: "Cache", value: formatTokens(summary.cacheRead + summary.cacheWrite), color: Palette.sun)
                    Chip(label: "Replies", value: summary.messages.formatted(), color: Palette.mint)
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
                    .fill((session.isBusy ? Palette.blue : Palette.mint).opacity(0.15))
                    .frame(width: 32, height: 32)
                if session.isBusy {
                    BouncingDots()
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Palette.mint)
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
                    .foregroundStyle(session.isBusy ? Palette.blue : Palette.text2)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.up.right")
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
        .onTapGesture {
            if let cwd = session.cwd { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
        }
        .animation(.spring(duration: 0.45, bounce: 0.55), value: session.isBusy)
        .help("Open \(session.folder) in Finder")
    }

    private var detail: String {
        let elapsed = session.statusSince.map { formatClock(now.timeIntervalSince($0)) } ?? ""
        return session.isBusy ? "Working · \(elapsed)" : "Done · \(session.shortFolder)"
    }
}

// MARK: - Greeting

struct Greeting {
    let text: String
    let symbol: String
    let color: Color

    static var now: Greeting {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return Greeting(text: "Good morning", symbol: "sun.max.fill", color: Palette.sun)
        case 12..<17: return Greeting(text: "Good afternoon", symbol: "sun.haze.fill", color: Palette.sun)
        case 17..<21: return Greeting(text: "Good evening", symbol: "sunset.fill", color: Palette.coral)
        default: return Greeting(text: "Late night coding", symbol: "moon.stars.fill", color: Palette.blue)
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
