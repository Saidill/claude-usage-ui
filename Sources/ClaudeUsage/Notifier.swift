import AppKit
import AVFoundation
import UserNotifications

final class Notifier {
    static let shared = Notifier()

    static let chime = "Chime"

    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    static var allSounds: [String] { [chime] + systemSounds }

    /// UNUserNotificationCenter crashes when the binary isn't inside an .app bundle (e.g. `swift run`).
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private lazy var chimePlayer: AVAudioPlayer? = try? AVAudioPlayer(data: Self.makeChimeWAV())

    private init() {
        UserDefaults.standard.register(defaults: [
            Settings.soundKey: Self.chime,
            Settings.soundEnabledKey: true,
            Settings.notifyKey: true,
            Settings.limitAlertsKey: true,
            Settings.limitThresholdKey: 80,
            Settings.resetPingKey: true,
        ])
        if canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func playSound(_ name: String? = nil) {
        let name = name ?? UserDefaults.standard.string(forKey: Settings.soundKey) ?? Self.chime
        if name == Self.chime {
            chimePlayer?.currentTime = 0
            chimePlayer?.play()
        } else {
            NSSound(named: NSSound.Name(name))?.play()
        }
    }

    func taskFinished(_ sessionName: String, banner: Bool = true) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Settings.soundEnabledKey) { playSound() }
        guard banner, defaults.bool(forKey: Settings.notifyKey) else { return }
        notify(title: "Claude is done", body: "\(sessionName) finished and is waiting for you.")
    }

    /// Shows a notification now, or at `date` when given. Reusing an `id` replaces the pending one.
    func notify(id: String = UUID().uuidString, title: String, body: String, at date: Date? = nil, sound: Bool = false) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let trigger = date.map {
            UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0),
                repeats: false)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(id: String) {
        guard canNotify else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Soft two-note bell (A5 then E6): sine partials with exponential decay, as an in-memory 16-bit mono WAV.
    private static func makeChimeWAV() -> Data {
        let sampleRate = 44_100
        let duration = 1.1
        let notes: [(freq: Double, start: Double)] = [(880.0, 0), (1318.51, 0.11)]
        var samples = [Double](repeating: 0, count: Int(duration * Double(sampleRate)))
        for note in notes {
            let offset = Int(note.start * Double(sampleRate))
            for i in 0..<(samples.count - offset) {
                let t = Double(i) / Double(sampleRate)
                let attack = min(1, t / 0.004)
                let body = sin(2 * .pi * note.freq * t) * exp(-t * 5.5)
                let shimmer = 0.25 * sin(2 * .pi * note.freq * 2.01 * t) * exp(-t * 9)
                samples[offset + i] += attack * (body + shimmer)
            }
        }
        let pcm = samples.map { Int16(max(-1, min(1, $0 * 0.32)) * Double(Int16.max)) }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = pcm.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        pcm.forEach { append($0) }
        return data
    }
}
