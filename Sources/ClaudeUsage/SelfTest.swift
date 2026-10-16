import AppKit
import SwiftUI

/// Drives the real app through mode switches and every notch state, checks that the right window is
/// visible and clickable each time, and saves a picture of each screen.
/// Run: ClaudeUsage.app/Contents/MacOS/ClaudeUsage --selftest <output folder>
@MainActor
enum SelfTest {
    private static var out = URL(fileURLWithPath: NSTemporaryDirectory())
    private static var report: [String] = []
    private static var failures = 0

    static func startIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest") else { return }
        if args.count > i + 1 { out = URL(fileURLWithPath: args[i + 1]) }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { await run() }
    }

    private static func run() async {
        let display = DisplayModeController.shared
        let notch = NotchWindowController.shared
        let original = display.setting
        notch.holdOpenForTesting = true
        await wait(1.5) // let the app finish launching
        renderDragons()

        for round in 1...3 {
            log("— Round \(round)")

            // Menu bar mode: the icon opens the popover.
            display.setting = .menuBar
            await wait(0.8)
            check(notch.window?.isVisible != true, "notch window hidden in menu bar mode")
            check(visibleIcons() == 1, "exactly one menu bar icon")
            await clickStatusItem()
            check(popoverWindow()?.isVisible == true, "popover opens from the menu bar icon")
            if round == 1, let w = popoverWindow() {
                snapshot(w, "1-menubar-popover")
                check(await dragonMoves(in: w), "dragon moves in the menu bar header")
            }

            // Header button inside the popover: switch to the notch while the popover is open.
            display.toggle()
            await wait(1.0)
            check(display.isNotch, "switched to notch mode")
            check(notch.window?.isVisible == true, "notch window visible")
            check(notch.window?.ignoresMouseEvents == true, "closed notch lets clicks through")
            check(popoverWindow()?.isVisible != true, "popover gone after switching to the notch")
            check(visibleIcons() == 0, "menu bar icon hidden in notch mode")

            // Open the notch, as hovering does.
            notch.open()
            await wait(0.9)
            check(notch.model.expanded, "notch opens")
            check(notch.window?.ignoresMouseEvents == false, "open notch takes clicks")
            if round == 1, let w = notch.window {
                snapshot(w, "2-notch-open")
                check(await dragonMoves(in: w), "dragon moves in the open notch header")
            }

            // Header button inside the notch: back to the menu bar while the notch is open.
            display.toggle()
            await wait(1.0)
            check(!display.isNotch, "switched back to menu bar mode")
            check(notch.window?.isVisible != true, "notch window hidden again")
            check(!notch.model.expanded, "notch state reset")
            check(visibleIcons() == 1, "exactly one menu bar icon after coming back")
            await clickStatusItem()
            check(popoverWindow()?.isVisible == true, "popover still opens after coming back from the notch")
            await clickStatusItem()
            check(popoverWindow()?.isVisible != true, "clicking the icon again closes it")
            await closePopover()

            // And to the notch again from the menu bar: it must open again.
            display.setting = .notch
            await wait(0.8)
            notch.open()
            await wait(0.9)
            check(notch.model.expanded && notch.window?.isVisible == true, "notch opens again after a round trip")
            notch.close()
            await wait(0.6)
            check(!notch.model.expanded && notch.window?.ignoresMouseEvents == true, "notch closes cleanly")
        }

        // Pictures of each popover tab.
        display.setting = .menuBar
        await wait(0.6)
        let originalTab = UserDefaults.standard.integer(forKey: "popoverTab")
        for (tab, name) in [(1, "5-menubar-recent"), (2, "6-menubar-usage"), (0, "")] {
            UserDefaults.standard.set(tab, forKey: "popoverTab")
            await clickStatusItem()
            await wait(0.8)
            if !name.isEmpty, let w = popoverWindow() { snapshot(w, name) }
            await closePopover()
        }
        UserDefaults.standard.set(originalTab, forKey: "popoverTab")

        // Pictures of the other notch states.
        display.setting = .notch
        await wait(0.8)
        if let panel = notch.window {
            // The closed hover zone must stay inside the menu bar, so browser tabs under the notch can't open it.
            let zone = notch.activeRect()
            let notchBottom = panel.frame.maxY - notch.model.notch.height
            check(zone.minY >= notchBottom - 0.5, "closed notch hover zone stays inside the menu bar")
            check(!zone.contains(NSPoint(x: panel.frame.midX, y: notchBottom - 12)), "pointer on a tab under the notch doesn't count")
        }
        if let w = notch.window { snapshot(w, AppModels.sessions.busyCount > 0 ? "3-notch-live" : "3-notch-closed") }
        notch.model.popped = LiveSession(pid: 1, sessionId: nil, cwd: NSHomeDirectory() + "/ProjectCode/claude-usage-ui",
                                         name: "claude-usage-ui", status: "idle", kind: nil, startedAt: nil,
                                         statusUpdatedAt: nil)
        await wait(1.0)
        if let w = notch.window { snapshot(w, "4-notch-finished-pop") }
        notch.model.popped = nil
        await wait(0.6)

        display.setting = original
        log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(what)")
    }

    private static func log(_ line: String) {
        report.append(line)
        print(line)
    }

    private static func clickStatusItem() async {
        StatusItemController.shared.statusButton?.performClick(nil)
        await wait(0.8)
    }

    private static func closePopover() async {
        StatusItemController.shared.close()
        await wait(0.4)
    }

    private static func popoverWindow() -> NSWindow? { StatusItemController.shared.panel }

    /// How many working menu bar icons this app has: status windows holding a button, placed in the menu bar.
    private static func visibleIcons() -> Int {
        let bars = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
        log("   status windows: " + bars.map {
            "vis=\($0.isVisible) button=\(find(NSStatusBarButton.self, in: $0.contentView) != nil) frame=\(NSStringFromRect($0.frame))"
        }.joined(separator: ", "))
        return bars.filter { $0.isVisible && find(NSStatusBarButton.self, in: $0.contentView) != nil }.count
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }

    /// Every dragon mood, large and at the sizes the app uses, on black.
    private static func renderDragons() {
        let moods: [DragonMood] = [.sleeping, .idle, .working, .happy]
        // The roar, frame by frame (one cycle is 2.6 s): building up, full fire, settling.
        let roar = [0.15, 0.4, 0.9, 1.5, 1.85].map { 2600.0 + $0 }
        let sheet = VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) { ForEach(moods.indices, id: \.self) { DragonView(mood: moods[$0], size: 160, at: 2600.5) } }
            HStack(spacing: 0) { ForEach(roar.indices, id: \.self) { DragonView(mood: .happy, size: 100, at: roar[$0], fireRoom: 0.6) } }
            HStack(spacing: 24) {
                ForEach(moods.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        DragonView(mood: moods[i], size: 44, at: 2601)
                        DragonView(mood: moods[i], size: 34, at: 2601)
                        DragonView(mood: moods[i], size: 26, at: 2601)
                    }
                    .frame(width: 160)
                }
            }
        }
        .padding(30)
        .background(Color.black)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: out.appendingPathComponent("0-dragons.png"))
        log("saved 0-dragons.png")
    }

    /// Captures the window twice, half a second apart, and checks that the header avatar (the dragon) changed.
    private static func dragonMoves(in window: NSWindow) async -> Bool {
        func capture() -> NSBitmapImageRep? {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }
        guard let a = capture() else { return false }
        await wait(0.5)
        guard let b = capture(), a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return false }
        // The avatar is the first thing on the left of the header: find the topmost opaque row, then scan below it.
        var top = 0
        while top < a.pixelsHigh - 1, (a.colorAt(x: a.pixelsWide / 2, y: top)?.alphaComponent ?? 0) < 0.5 { top += 1 }
        let scale = a.pixelsWide / Int(window.frame.width)
        let notchOffset = window === NotchWindowController.shared.window ? Int(NotchWindowController.shared.model.notch.height) - 8 : 0
        let x0 = (window.frame.width > 400 ? (Int(window.frame.width) - 376) / 2 : 0) * scale
        let y0 = top + notchOffset * scale
        var changed = 0
        for y in y0..<min(a.pixelsHigh, y0 + 70 * scale) {
            for x in x0..<min(a.pixelsWide, x0 + 70 * scale) where a.colorAt(x: x, y: y) != b.colorAt(x: x, y: y) {
                changed += 1
            }
        }
        log("   \(changed) pixels changed around the dragon")
        return changed > 20
    }

    private static func snapshot(_ window: NSWindow, _ name: String) {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Composite on a desktop-like grey so the glass and black edges are visible in the picture.
        let size = view.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.32, green: 0.34, blue: 0.38, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        log("saved \(name).png")
    }
}
