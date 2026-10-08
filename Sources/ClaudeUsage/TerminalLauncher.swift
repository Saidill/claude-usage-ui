import AppKit

/// Brings a running session's terminal to the front, or reopens a past session in a new Terminal window.
enum TerminalLauncher {
    private static let terminalID = "com.apple.Terminal"
    private static let iTermID = "com.googlecode.iterm2"
    /// Editors where opening the session's folder focuses the window that already has it open.
    private static let editorIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf", "dev.zed.Zed",
    ]

    // MARK: Jump to a live session

    static func focus(_ session: LiveSession) {
        guard let app = hostApp(of: session.pid) else {
            revealInFinder(session)
            return
        }
        let bundleID = app.bundleIdentifier ?? ""

        if bundleID == terminalID || bundleID == iTermID, let tty = tty(of: session.pid) {
            let script = bundleID == terminalID ? terminalScript(tty: tty) : iTermScript(tty: tty)
            runAppleScript(script) { ok in if !ok { app.activate() } }
        } else if editorIDs.contains(bundleID), let cwd = session.cwd, let appURL = app.bundleURL {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            app.activate()
        }
    }

    static func revealInFinder(_ session: LiveSession) {
        if let cwd = session.cwd { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
    }

    // MARK: Resume a past session

    /// Opens Terminal running `claude --resume <id>` in the session's folder.
    /// Uses a .command file, so no Automation permission is needed.
    static func resume(sessionId: String, cwd: String?) {
        guard sessionId.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return }
        let fm = FileManager.default
        let folder = cwd.flatMap { fm.fileExists(atPath: $0) ? $0 : nil } ?? NSHomeDirectory()
        let quoted = "'" + folder.replacingOccurrences(of: "'", with: "'\\''") + "'"

        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeUsage")
        let file = dir.appendingPathComponent("resume-\(sessionId.prefix(8)).command")
        let script = "#!/bin/zsh -l\ncd \(quoted) && clear && exec claude --resume \(sessionId)\n"
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            NSSound.beep()
        }
    }

    // MARK: Process helpers

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// Walks up the parent chain to the first regular app (Terminal, iTerm, VS Code, …).
    private static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            guard let parent = processInfo(current)?.kp_eproc.e_ppid, parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                return app
            }
            current = parent
        }
        return nil
    }

    /// e.g. "/dev/ttys003"
    private static func tty(of pid: pid_t) -> String? {
        guard let dev = processInfo(pid)?.kp_eproc.e_tdev, dev != -1,
              let name = devname(dev, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    // MARK: AppleScript

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    private static func iTermScript(tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    /// Runs off the main thread so the first-time permission prompt doesn't freeze the popover.
    private static func runAppleScript(_ source: String, completion: @escaping @MainActor (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var ok = false
            if (try? process.run()) != nil {
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                ok = process.terminationStatus == 0 && out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(ok) } }
        }
    }
}
