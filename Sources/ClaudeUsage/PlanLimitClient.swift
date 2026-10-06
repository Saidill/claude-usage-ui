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

    var fiveHourPercent: Double? { windows.first { $0.id == "five_hour" }?.utilization }

    private var timer: Timer?
    /// Set after an HTTP 429 so we stop asking until the server says it's OK again.
    private var backoffUntil: Date?

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        if let backoffUntil, Date() < backoffUntil { return }
        do {
            guard let token = await Self.readAccessToken() else {
                error = "Not logged in to Claude Code (no credentials found)."
                return
            }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 {
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
                backoffUntil = Date().addingTimeInterval(max(60, retryAfter))
                error = "Rate limited, retrying in a few minutes."
                return
            }
            guard status == 200 else {
                error = status == 401
                    ? "Token expired. Run `claude` once to refresh it."
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
        } catch {
            self.error = "Plan limits unavailable (offline?)."
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

    /// Claude Code stores its OAuth credentials in the login Keychain (or ~/.claude/.credentials.json on some setups).
    private static func readAccessToken() async -> String? {
        await Task.detached(priority: .utility) {
            var raw: Data?
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                raw = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 { raw = nil }
            }
            if raw == nil {
                let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.credentials.json")
                raw = try? Data(contentsOf: file)
            }
            guard let raw,
                  let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String else { return nil }
            return token
        }.value
    }
}
