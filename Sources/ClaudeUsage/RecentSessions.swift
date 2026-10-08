import Foundation

struct RecentSession: Identifiable, Equatable {
    let id: String // sessionId
    let title: String
    let cwd: String?
    let lastActive: Date

    /// Last two path components, e.g. "ProjectCode/claude-usage-ui".
    var shortFolder: String {
        guard let cwd else { return "" }
        return URL(fileURLWithPath: cwd).pathComponents.suffix(2).joined(separator: "/")
    }
}

/// Past Claude Code conversations, read from the newest transcripts in ~/.claude/projects.
/// Loads only on demand (when the Recent tab opens) and reads just the end of each file.
@MainActor
final class RecentSessionStore: ObservableObject {
    @Published private(set) var items: [RecentSession] = []
    @Published private(set) var loaded = false

    private let engine = Engine()

    func load(excluding liveIds: Set<String>) {
        engine.scan { [weak self] found in
            Task { @MainActor in
                guard let self else { return }
                let visible = found.filter { !liveIds.contains($0.id) }
                if self.items != visible { self.items = visible }
                self.loaded = true
            }
        }
    }

    final class Engine: @unchecked Sendable {
        private let queue = DispatchQueue(label: "recent-sessions", qos: .utility)
        private let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        private var cache: [String: (modified: Date, session: RecentSession?)] = [:]
        private let limit = 12
        private let tailBytes: UInt64 = 64 * 1024

        func scan(completion: @escaping @Sendable ([RecentSession]) -> Void) {
            queue.async {
                completion(self.newest())
            }
        }

        private func newest() -> [RecentSession] {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.contentModificationDateKey]
            let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []

            var files: [(url: URL, modified: Date)] = []
            for project in projects {
                // Top level only; subfolders hold subagent transcripts.
                let entries = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: keys)) ?? []
                for url in entries where url.pathExtension == "jsonl" {
                    let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                    files.append((url, modified))
                }
            }
            files.sort { $0.modified > $1.modified }

            var result: [RecentSession] = []
            for file in files where result.count < limit {
                let path = file.url.path
                if let cached = cache[path], cached.modified == file.modified {
                    if let s = cached.session { result.append(s) }
                    continue
                }
                let session = read(file.url, modified: file.modified)
                cache[path] = (file.modified, session)
                if let session { result.append(session) }
            }
            return result
        }

        /// Reads the tail of a transcript for its latest title and folder.
        private func read(_ url: URL, modified: Date) -> RecentSession? {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { return nil }
            try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
            guard let data = try? handle.readToEnd() else { return nil }

            var aiTitle: String?
            var lastPrompt: String?
            var cwd: String?
            // Newest lines last; walk backwards and stop once everything is found.
            for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if aiTitle == nil, obj["type"] as? String == "ai-title" { aiTitle = obj["aiTitle"] as? String }
                if lastPrompt == nil, obj["type"] as? String == "last-prompt" { lastPrompt = obj["lastPrompt"] as? String }
                if cwd == nil { cwd = obj["cwd"] as? String }
                if aiTitle != nil, cwd != nil { break }
            }

            guard var title = (aiTitle ?? lastPrompt)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " "), !title.isEmpty else { return nil }
            // AI titles are slugs like "docker-memory-usage-normal".
            if aiTitle != nil, !title.contains(" ") {
                title = title.replacingOccurrences(of: "-", with: " ")
                title = title.prefix(1).uppercased() + title.dropFirst()
            }
            return RecentSession(id: url.deletingPathExtension().lastPathComponent, title: title,
                                 cwd: cwd, lastActive: modified)
        }
    }
}
