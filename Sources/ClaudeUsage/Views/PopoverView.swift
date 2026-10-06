import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var usage: UsageTracker
    @EnvironmentObject var limits: PlanLimitClient
    @State private var showSettings = false
    @State private var range = 0 // 0 = today, 1 = week

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

            if showSettings {
                SettingsView()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            } else {
                Group {
                    limitsSection.padding(.bottom, 20)
                    Hairline()
                    tasksSection.padding(.vertical, 18)
                    Hairline()
                    tokensSection.padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 0)
                Color.clear.frame(height: 20)
            }
        }
        .frame(width: 344)
        .background(Palette.bg)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.18), value: showSettings)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(showSettings ? "Settings" : "Claude")
                    .font(.display(21))
                    .foregroundStyle(Palette.text)
                HStack(spacing: 2) {
                    PulsingDot(color: Palette.accent, size: 4.5)
                        .frame(width: 10, height: 10)
                    Text("Live · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                        .font(.small)
                        .foregroundStyle(Palette.text3)
                }
                .offset(x: -2)
            }
            Spacer()
            if !showSettings {
                IconButton(systemName: "arrow.clockwise", help: "Refresh") {
                    usage.refresh()
                    Task { await limits.refresh() }
                }
            }
            IconButton(systemName: showSettings ? "xmark" : "slider.horizontal.3", help: "Settings") {
                showSettings.toggle()
            }
            IconButton(systemName: "power", help: "Quit") { NSApp.terminate(nil) }
        }
    }

    // MARK: Limits

    private var sessionWindow: LimitWindow? { limits.windows.first { $0.id == "five_hour" } }
    private var weekWindow: LimitWindow? { limits.windows.first { $0.id == "seven_day" } }

    private var limitsSection: some View {
        HStack(alignment: .center, spacing: 20) {
            LimitDial(outer: sessionWindow?.utilization, inner: weekWindow?.utilization)

            VStack(alignment: .leading, spacing: 14) {
                if limits.windows.isEmpty {
                    Text(limits.error ?? "Reading your plan limits…")
                        .font(.small)
                        .foregroundStyle(Palette.text3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(limits.windows) { window in
                        LimitLegendRow(window: window, color: legendColor(window))
                    }
                    if let error = limits.error {
                        Text(error).font(.small).foregroundStyle(Palette.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendColor(_ w: LimitWindow) -> Color {
        switch w.id {
        case "five_hour": return LimitDial.sessionColor(w.utilization)
        case "seven_day": return Palette.sand
        default: return Palette.text3
        }
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Sessions") {
                if !sessions.sessions.isEmpty {
                    Text("\(sessions.busyCount) working · \(sessions.sessions.count - sessions.busyCount) waiting")
                        .font(.small).foregroundStyle(Palette.text3)
                }
            }
            if sessions.sessions.isEmpty {
                Text("Nothing running. Start `claude` in a terminal and it appears here.")
                    .font(.small).foregroundStyle(Palette.text3)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        ForEach(sessions.sessions) { session in
                            SessionRow(session: session, now: context.date)
                        }
                    }
                }
            }
        }
    }

    // MARK: Tokens

    private var tokensSection: some View {
        let week = range == 1
        let summary = week ? usage.lastSevenDays : usage.today
        let models = week ? usage.weekByModel : usage.todayByModel

        return VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Tokens") { TextSwitch(options: ["Today", "7 days"], selection: $range) }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatTokens(summary.total))
                    .font(.display(38))
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: summary.total)
                Text("tokens").font(.body13).foregroundStyle(Palette.text3)
                Spacer()
                Text("\(summary.messages.formatted()) replies")
                    .font(.small).foregroundStyle(Palette.text3)
            }

            if week {
                BarChart(
                    values: usage.weekByDay,
                    labels: weekdayLabels,
                    centerLabels: true,
                    highlight: 6,
                    tooltips: usage.weekByDay.map { formatTokens($0) }
                )
            } else {
                let hour = Calendar.current.component(.hour, from: Date())
                BarChart(
                    values: usage.todayByHour,
                    labels: ["00", "06", "12", "18"],
                    highlight: hour,
                    future: hour + 1,
                    tooltips: usage.todayByHour.enumerated().map { String(format: "%02d:00 · ", $0.offset) + formatTokens($0.element) }
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Stat(label: "Output", value: summary.output)
                    Stat(label: "Input", value: summary.input)
                    Stat(label: "Last 5 hours", value: usage.lastFiveHours.total)
                }
                GridRow {
                    Stat(label: "Cache read", value: summary.cacheRead)
                    Stat(label: "Cache write", value: summary.cacheWrite)
                    Color.clear.frame(height: 1)
                }
            }

            if !models.isEmpty { ModelSplit(models: models).padding(.top, 2) }
        }
    }

    private var weekdayLabels: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i - 6, to: today)!
            return day.formatted(.dateTime.weekday(.abbreviated))
        }
    }
}

// MARK: - Rows

struct LimitLegendRow: View {
    let window: LimitWindow
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(window.title).font(.body13).foregroundStyle(Palette.text)
                Spacer(minLength: 4)
                Text("\(Int(window.utilization.rounded()))%")
                    .font(.body13.monospacedDigit())
                    .foregroundStyle(Palette.text2)
            }
            if let reset = window.resetsAt {
                Text(formatReset(reset))
                    .font(.small)
                    .foregroundStyle(Palette.text3)
                    .padding(.leading, 13)
            }
        }
    }
}

struct SessionRow: View {
    let session: LiveSession
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if session.isBusy {
                    PulsingDot()
                } else {
                    Circle().strokeBorder(Palette.text3, lineWidth: 1).frame(width: 7, height: 7)
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.body13.weight(.medium))
                    .foregroundStyle(session.isBusy ? Palette.text : Palette.text2)
                    .lineLimit(1)
                Text(session.shortFolder)
                    .font(.small)
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(session.isBusy ? "Working" : "Waiting")
                    .font(.small)
                    .foregroundStyle(session.isBusy ? Palette.accent : Palette.text3)
                if let since = session.statusSince {
                    Text(formatClock(now.timeIntervalSince(since)))
                        .font(.small.monospacedDigit())
                        .foregroundStyle(Palette.text3)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(session.isBusy || hovering ? Palette.surface : .clear)
        )
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
        .help(session.folder)
    }
}

struct Stat: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.text3)
            Text(formatTokens(value)).font(.body13.monospacedDigit()).foregroundStyle(Palette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    if s <= 0 { return "Resetting now" }
    if s < 24 * 3600 {
        let h = Int(s) / 3600, m = Int(s) % 3600 / 60
        return h > 0 ? "Resets in \(h)h \(m)m" : "Resets in \(m)m"
    }
    return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}
