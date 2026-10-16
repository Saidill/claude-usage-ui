import Foundation

struct LimitWindow: Identifiable, Equatable {
    let id: String
    let utilization: Double // 0...100
    let resetsAt: Date?

    var title: String {
        switch id {
        case "five_hour": return "Session"
        case "seven_day": return "Week"
        case "seven_day_opus": return "Opus week"
        case "seven_day_sonnet": return "Sonnet week"
        default: return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var sortOrder: Int {
        ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"].firstIndex(of: id) ?? 99
    }
}

/// Reads plan-limit usage (the numbers `/usage` shows in Claude Code).
/// NOTE: this uses an undocumented endpoint and Claude Code's OAuth token; it may stop working at any time.
@MainActor
final class PlanLimitClient: ObservableObject {
    @Published private(set) var windows: [LimitWindow] = []
    @Published private(set) var error: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    /// Where the session limit is heading at the current pace; nil until there's enough history.
    @Published private(set) var forecast: LimitForecast?

    /// Recent session-limit readings, kept across restarts so the pace isn't lost.
    private var samples: [LimitForecast.Sample] = []
    private var samplesWindow: Double = 0
    private static let samplesKey = "forecast.samples"
    private static let samplesWindowKey = "forecast.window"

    var fiveHourPercent: Double? { windows.first { $0.id == "five_hour" }?.utilization }

    private var timer: Timer?
    /// Set after an HTTP 429 so we stop asking until the server says it's OK again.
    private var backoffUntil: Date?

    init() {
        let defaults = UserDefaults.standard
        samples = defaults.data(forKey: Self.samplesKey)
            .flatMap { try? JSONDecoder().decode([LimitForecast.Sample].self, from: $0) } ?? []
        samplesWindow = defaults.double(forKey: Self.samplesWindowKey)
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Refreshes unless the numbers are only a few seconds old (used when the popover opens).
    func refreshIfStale() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 20 { return }
        await refresh()
    }

    func refresh() async {
        if let backoffUntil, Date() < backoffUntil { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard var creds = await Credentials.read() else {
                error = "Not logged in to Claude Code (no credentials found)."
                return
            }
            // Claude Code only renews its token while it runs; renew it here so limits keep updating when you only chat.
            if creds.expiresSoon {
                guard let renewed = await Credentials.refresh(creds) else {
                    error = "Login expired. Run `claude` once to log in again."
                    return
                }
                creds = renewed
            }

            var (data, status, response) = try await fetchUsage(token: creds.accessToken)
            if status == 401, let renewed = await Credentials.refresh(creds) {
                (data, status, response) = try await fetchUsage(token: renewed.accessToken)
            }
            if status == 429 {
                let retryAfter = response?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
                backoffUntil = Date().addingTimeInterval(max(60, retryAfter))
                error = "Rate limited, retrying in a few minutes."
                return
            }
            guard status == 200 else {
                error = status == 401
                    ? "Login expired. Run `claude` once to log in again."
                    : "Plan limits unavailable (HTTP \(status))."
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                error = "Unexpected response."
                return
            }
            windows = Self.parse(json)
            error = windows.isEmpty ? "No limit data returned." : nil
            lastUpdated = Date()
            recordSample()
            checkAlerts()
        } catch {
            self.error = "Plan limits unavailable (offline?)."
        }
    }

    private func fetchUsage(token: String) async throws -> (Data, Int, HTTPURLResponse?) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return (data, http?.statusCode ?? 0, http)
    }

    /// Adds the latest session reading to the history and updates the forecast.
    private func recordSample() {
        guard let session = windows.first(where: { $0.id == "five_hour" }) else { return }
        let now = Date()
        // A new reset time (or a drop in usage) means a new window: start the history over.
        let window = session.resetsAt?.timeIntervalSince1970 ?? 0
        if abs(window - samplesWindow) > 60 || (samples.last.map { session.utilization < $0.percent - 1 } ?? false) {
            samples = []
            samplesWindow = window
        }
        samples.append(.init(date: now, percent: session.utilization))
        samples.removeAll { now.timeIntervalSince($0.date) > LimitForecast.lookback }

        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(samples), forKey: Self.samplesKey)
        defaults.set(samplesWindow, forKey: Self.samplesWindowKey)
        forecast = LimitForecast.make(from: samples, now: now, resetsAt: session.resetsAt)
    }

    /// Warns once per reset window when a limit crosses the threshold, and schedules a ping for when the session limit resets.
    private func checkAlerts() {
        let defaults = UserDefaults.standard
        let threshold = Double(defaults.integer(forKey: Settings.limitThresholdKey))
        let now = Date()

        if defaults.bool(forKey: Settings.limitAlertsKey) {
            for w in windows where ["five_hour", "seven_day"].contains(w.id) && w.utilization >= threshold {
                let key = "alerted.\(w.id).\(Int(w.resetsAt?.timeIntervalSince1970 ?? 0))"
                guard !defaults.bool(forKey: key) else { continue }
                defaults.set(true, forKey: key)
                let reset = w.resetsAt.map { ", " + formatReset($0) } ?? ""
                Notifier.shared.notify(title: "\(w.title) limit at \(Int(w.utilization.rounded()))%",
                                       body: "Heads up: you're close to your \(w.title.lowercased()) limit\(reset).")
            }
            // Warn once per window when the current pace fills the session limit within half an hour.
            if case .hitsLimit(let full)? = forecast, full.timeIntervalSince(now) < 30 * 60,
               let session = windows.first(where: { $0.id == "five_hour" }) {
                let key = "alerted.forecast.\(Int(session.resetsAt?.timeIntervalSince1970 ?? 0))"
                if !defaults.bool(forKey: key) {
                    defaults.set(true, forKey: key)
                    Notifier.shared.notify(title: "On pace to hit your session limit",
                                           body: "At this pace it fills around \(full.formatted(date: .omitted, time: .shortened)).")
                }
            }
            // Forget alerts for windows that have already reset.
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("alerted.") {
                if let epoch = key.split(separator: ".").last.flatMap({ Double($0) }), epoch > 0,
                   Date(timeIntervalSince1970: epoch) < now {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        if let session = windows.first(where: { $0.id == "five_hour" }) {
            if defaults.bool(forKey: Settings.resetPingKey), session.utilization >= threshold,
               let reset = session.resetsAt, reset > now {
                Notifier.shared.notify(id: "reset.five_hour", title: "Your session limit has reset",
                                       body: "Back to full speed ✨", at: reset,
                                       sound: defaults.bool(forKey: Settings.soundEnabledKey))
            } else {
                Notifier.shared.cancel(id: "reset.five_hour")
            }
        }
    }

    private static func parse(_ json: [String: Any]) -> [LimitWindow] {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        return json.compactMap { key, value -> LimitWindow? in
            guard let dict = value as? [String: Any],
                  let util = (dict["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (dict["resets_at"] as? String).flatMap { isoFrac.date(from: $0) ?? iso.date(from: $0) }
            return LimitWindow(id: key, utilization: util, resetsAt: reset)
        }
        .sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
    }
}

/// Claude Code's OAuth credentials, stored in the login Keychain (or ~/.claude/.credentials.json on some setups).
private struct Credentials {
    enum Source { case keychain(account: String), file(URL) }

    static let service = "Claude Code-credentials"
    static let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.credentials.json")
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenURLs = ["https://platform.claude.com/v1/oauth/token", "https://console.anthropic.com/v1/oauth/token"]

    let source: Source
    /// The whole stored JSON, so every field Claude Code keeps survives a write-back.
    let json: [String: Any]

    var oauth: [String: Any] { json["claudeAiOauth"] as? [String: Any] ?? [:] }
    var accessToken: String { oauth["accessToken"] as? String ?? "" }
    var refreshToken: String? { oauth["refreshToken"] as? String }
    var expiresSoon: Bool {
        guard let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue else { return false }
        return Date(timeIntervalSince1970: ms / 1000) < Date().addingTimeInterval(5 * 60)
    }

    static func read() async -> Credentials? {
        await Task.detached(priority: .utility) { readSync() }.value
    }

    private static func readSync() -> Credentials? {
        if let account = keychainAccount(),
           let out = run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"]),
           let creds = parse(out, source: .keychain(account: account)) {
            return creds
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(data, source: .file(file))
    }

    private static func parse(_ data: Data, source: Source) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              oauth["accessToken"] is String else { return nil }
        return Credentials(source: source, json: json)
    }

    private static func keychainAccount() -> String? {
        guard let out = run("/usr/bin/security", ["find-generic-password", "-s", service]),
              let text = String(data: out, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.contains("\"acct\"") }),
              let start = line.range(of: "=\"") else { return nil }
        return String(line[start.upperBound...].dropLast())
    }

    private static let refreshLock = RefreshLock()

    /// Exchanges the refresh token for a new access token and saves both back where Claude Code reads them.
    /// The refresh token rotates, so the write-back is what keeps Claude Code logged in.
    static func refresh(_ stale: Credentials) async -> Credentials? {
        await refreshLock.run {
            // Claude Code may have just renewed it; use that instead of rotating again.
            guard let current = await read() else { return nil }
            if current.accessToken != stale.accessToken, !current.expiresSoon { return current }
            guard let refreshToken = current.refreshToken else { return nil }

            let body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]
            for url in tokenURLs {
                var request = URLRequest(url: URL(string: url)!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 15
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let access = reply["access_token"] as? String else { continue }

                var oauth = current.oauth
                oauth["accessToken"] = access
                if let rotated = reply["refresh_token"] as? String { oauth["refreshToken"] = rotated }
                if let expiresIn = (reply["expires_in"] as? NSNumber)?.doubleValue {
                    oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
                }
                var json = current.json
                json["claudeAiOauth"] = oauth
                let renewed = Credentials(source: current.source, json: json)
                await Task.detached(priority: .utility) { renewed.save() }.value
                return renewed
            }
            return nil
        }
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        switch source {
        case .keychain(let account):
            _ = Self.run("/usr/bin/security", ["add-generic-password", "-U", "-s", Self.service, "-a", account, "-w", text])
        case .file(let url):
            try? data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Runs a command and returns its stdout, or nil if it failed.
    private static func run(_ path: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? out : nil
    }
}

/// Lets only one token refresh run at a time, so two callers never rotate the same refresh token.
private actor RefreshLock {
    private var busy = false

    func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        while busy { await Task.yield() }
        busy = true
        defer { busy = false }
        return await work()
    }
}
