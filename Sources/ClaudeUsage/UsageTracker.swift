import Foundation

struct UsageRecord {
    let date: Date
    let model: String
    let input: Int
    let output: Int
    let cacheWrite5m: Int
    let cacheWrite1h: Int
    let cacheRead: Int
}

struct UsageSummary: Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var messages = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    mutating func add(_ r: UsageRecord) {
        input += r.input
        output += r.output
        cacheWrite += r.cacheWrite5m + r.cacheWrite1h
        cacheRead += r.cacheRead
        messages += 1
    }
}

struct ModelUsage: Identifiable, Equatable {
    let model: String
    let summary: UsageSummary
    var id: String { model }
}

/// Incrementally tails Claude Code transcripts (~/.claude/projects/**/*.jsonl) and aggregates token usage.
@MainActor
final class UsageTracker: ObservableObject {
    @Published private(set) var today = UsageSummary()
    @Published private(set) var lastFiveHours = UsageSummary()
    @Published private(set) var lastSevenDays = UsageSummary()
    @Published private(set) var todayByModel: [ModelUsage] = []
    @Published private(set) var weekByModel: [ModelUsage] = []
    /// Tokens per hour of the current day (24 buckets).
    @Published private(set) var todayByHour: [Int] = Array(repeating: 0, count: 24)
    /// Tokens per day for the last 7 days; index 6 is today.
    @Published private(set) var weekByDay: [Int] = Array(repeating: 0, count: 7)
    @Published private(set) var lastUpdated: Date?

    private let engine = Engine()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        engine.scan { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if self.today != result.today { self.today = result.today }
                if self.lastFiveHours != result.fiveHours { self.lastFiveHours = result.fiveHours }
                if self.lastSevenDays != result.week { self.lastSevenDays = result.week }
                if self.todayByModel != result.todayByModel { self.todayByModel = result.todayByModel }
                if self.weekByModel != result.weekByModel { self.weekByModel = result.weekByModel }
                if self.todayByHour != result.todayByHour { self.todayByHour = result.todayByHour }
                if self.weekByDay != result.weekByDay { self.weekByDay = result.weekByDay }
                self.lastUpdated = Date()
            }
        }
    }

    struct Result {
        var today = UsageSummary()
        var fiveHours = UsageSummary()
        var week = UsageSummary()
        var todayByModel: [ModelUsage] = []
        var weekByModel: [ModelUsage] = []
        var todayByHour: [Int] = Array(repeating: 0, count: 24)
        var weekByDay: [Int] = Array(repeating: 0, count: 7)
    }

    /// All file I/O happens on a private serial queue.
    final class Engine: @unchecked Sendable {
        private let queue = DispatchQueue(label: "usage-tracker", qos: .utility)
        private let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        private var offsets: [String: UInt64] = [:]
        private var records: [String: UsageRecord] = [:]
        private var busy = false
        private let retention: TimeInterval = 8 * 24 * 3600
        private let usageMarker = Data("\"usage\"".utf8)

        private let isoFrac: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private let iso = ISO8601DateFormatter()

        func scan(completion: @escaping @Sendable (Result) -> Void) {
            queue.async {
                guard !self.busy else { return }
                self.busy = true
                defer { self.busy = false }
                self.readNewLines()
                completion(self.aggregate())
            }
        }

        private func readNewLines() {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
            let cutoff = Date().addingTimeInterval(-retention)

            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.fileSize.map(UInt64.init),
                      (values.contentModificationDate ?? .distantPast) > cutoff else { continue }

                let path = url.path
                var offset = offsets[path] ?? 0
                if size < offset { offset = 0 } // file was truncated / replaced
                guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? handle.close() }

                do {
                    try handle.seek(toOffset: offset)
                    guard let data = try handle.readToEnd(),
                          let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { continue }
                    let complete = data[data.startIndex...lastNewline]
                    for line in complete.split(separator: UInt8(ascii: "\n")) {
                        parse(Data(line), fallbackKey: "\(path):\(offset)")
                    }
                    offsets[path] = offset + UInt64(complete.count)
                } catch {
                    continue
                }
            }

            records = records.filter { $0.value.date > cutoff }
        }

        private func parse(_ line: Data, fallbackKey: String) {
            guard line.range(of: usageMarker) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let ts = obj["timestamp"] as? String,
                  let date = isoFrac.date(from: ts) ?? iso.date(from: ts) else { return }

            let model = message["model"] as? String ?? "unknown"
            guard model != "<synthetic>" else { return }

            func int(_ dict: [String: Any]?, _ key: String) -> Int { (dict?[key] as? NSNumber)?.intValue ?? 0 }

            let cacheCreation = usage["cache_creation"] as? [String: Any]
            let totalWrite = int(usage, "cache_creation_input_tokens")
            let write1h = int(cacheCreation, "ephemeral_1h_input_tokens")
            let write5m = cacheCreation == nil ? totalWrite : max(0, totalWrite - write1h)

            let record = UsageRecord(
                date: date,
                model: model,
                input: int(usage, "input_tokens"),
                output: int(usage, "output_tokens"),
                cacheWrite5m: write5m,
                cacheWrite1h: write1h,
                cacheRead: int(usage, "cache_read_input_tokens")
            )
            // A single API response is written as several lines (one per content block); keep the latest.
            let key = (message["id"] as? String).map { $0 + ((obj["requestId"] as? String) ?? "") } ?? fallbackKey
            records[key] = record
        }

        private func aggregate() -> Result {
            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
            let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)

            var result = Result()
            var todayModels: [String: UsageSummary] = [:]
            var weekModels: [String: UsageSummary] = [:]

            let calendar = Calendar.current
            for r in records.values {
                let tokens = r.input + r.output + r.cacheWrite5m + r.cacheWrite1h + r.cacheRead
                let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: r.date), to: startOfDay).day ?? 99
                if (0..<7).contains(daysAgo) { result.weekByDay[6 - daysAgo] += tokens }
                if r.date >= weekAgo {
                    result.week.add(r)
                    weekModels[r.model, default: UsageSummary()].add(r)
                }
                if r.date >= startOfDay {
                    result.today.add(r)
                    todayModels[r.model, default: UsageSummary()].add(r)
                    result.todayByHour[calendar.component(.hour, from: r.date)] += tokens
                }
                if r.date >= fiveHoursAgo { result.fiveHours.add(r) }
            }

            func sorted(_ dict: [String: UsageSummary]) -> [ModelUsage] {
                dict.map { ModelUsage(model: $0.key, summary: $0.value) }.sorted { $0.summary.total > $1.summary.total }
            }
            result.todayByModel = sorted(todayModels)
            result.weekByModel = sorted(weekModels)
            return result
        }
    }
}

/// Short, readable model name, e.g. "claude-opus-5-5" -> "opus-5.5".
func prettyModelName(_ model: String) -> String {
    var parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
    // Drop date suffixes like 20251001.
    parts.removeAll { $0.count == 8 && Int($0) != nil }
    guard let family = parts.first else { return model }
    let version = parts.dropFirst().joined(separator: ".")
    return version.isEmpty ? family : "\(family)-\(version)"
}
