import Foundation

/// Where the session limit is heading, judged from how fast it has been filling lately.
enum LimitForecast: Equatable {
    /// No usage in the last few minutes.
    case idle
    /// At this pace the limit resets before it fills.
    case makesIt
    /// At this pace the limit fills at this time.
    case hitsLimit(at: Date)

    struct Sample: Codable, Equatable {
        let date: Date
        let percent: Double
    }

    /// Only the last half hour counts, so the forecast follows how you're working right now.
    static let lookback: TimeInterval = 30 * 60

    /// Fits a straight line through the recent samples. Nil until there are at least 3 samples spanning 5 minutes.
    static func make(from samples: [Sample], now: Date = Date(), resetsAt: Date?) -> LimitForecast? {
        let recent = samples.filter { now.timeIntervalSince($0.date) <= lookback }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 5 * 60, last.percent < 100 else { return nil }

        // Least-squares slope, in percent per second.
        let xs = recent.map { $0.date.timeIntervalSince(first.date) }
        let ys = recent.map(\.percent)
        let n = Double(recent.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx

        if slope * 60 <= 0.01 { return .idle }
        let full = now.addingTimeInterval((100 - last.percent) / slope)
        if let resetsAt, full >= resetsAt { return .makesIt }
        return .hitsLimit(at: full)
    }
}
