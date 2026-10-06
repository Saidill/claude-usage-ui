import Foundation

struct LiveSession: Identifiable, Decodable, Equatable {
    let pid: Int32
    let sessionId: String?
    let cwd: String?
    let name: String?
    let status: String?
    let kind: String?
    let startedAt: Double?
    let statusUpdatedAt: Double?

    var id: Int32 { pid }
    var isBusy: Bool { status == "busy" }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let cwd { return URL(fileURLWithPath: cwd).lastPathComponent }
        return "Session \(pid)"
    }

    /// Full path with ~ for the home folder.
    var folder: String {
        guard let cwd else { return "" }
        return cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Last two path components, e.g. "ProjectCode/claude-usage-ui".
    var shortFolder: String {
        guard let cwd else { return "" }
        return URL(fileURLWithPath: cwd).pathComponents.suffix(2).joined(separator: "/")
    }

    var statusSince: Date? {
        (statusUpdatedAt ?? startedAt).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// Watches ~/.claude/sessions/*.json, which Claude Code keeps updated for every running session.
@MainActor
final class SessionMonitor: ObservableObject {
    @Published private(set) var sessions: [LiveSession] = []

    var busyCount: Int { sessions.filter(\.isBusy).count }

    private let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")
    private var lastStatus: [Int32: String] = [:]
    private var firstScan = true
    private var timer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?

    init() {
        scan()
        watchDirectory()
        // Fallback: status changes rewrite files in place, which a directory watch may not see.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func watchDirectory() {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var found: [LiveSession] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(LiveSession.self, from: data),
                  Self.isAlive(session.pid) else { continue }
            found.append(session)
        }
        found.sort { ($0.isBusy ? 0 : 1, $0.displayName) < ($1.isBusy ? 0 : 1, $1.displayName) }

        for session in found {
            let previous = lastStatus[session.pid]
            if !firstScan, previous == "busy", !session.isBusy {
                Notifier.shared.taskFinished(session.displayName)
            }
            lastStatus[session.pid] = session.status ?? ""
        }
        let alive = Set(found.map(\.pid))
        lastStatus = lastStatus.filter { alive.contains($0.key) }
        firstScan = false

        if found != sessions { sessions = found }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
