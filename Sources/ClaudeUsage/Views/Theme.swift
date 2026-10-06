import AppKit
import SwiftUI

// MARK: - Colours & type

enum Palette {
    static let bg = Color.dynamic(light: 0xF4F6FB, dark: 0x13151B)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1D2028)
    static let line = Color.dynamic(light: 0xECEFF5, dark: 0x2A2E39)
    static let text = Color.dynamic(light: 0x1B1F2E, dark: 0xF2F3F7)
    static let text2 = Color.dynamic(light: 0x676D82, dark: 0xA3A8BA)
    static let text3 = Color.dynamic(light: 0xA6ABBB, dark: 0x6A7084)

    static let blue = Color.dynamic(light: 0x3D7BFF, dark: 0x5B8FFF)
    static let mint = Color.dynamic(light: 0x14C495, dark: 0x2EE0B0)
    static let sun = Color.dynamic(light: 0xFFB020, dark: 0xFFC247)
    static let coral = Color.dynamic(light: 0xFF5C7C, dark: 0xFF7590)

    static let confetti: [Color] = [blue, mint, sun, coral]

    /// Base colour while usage is comfortable, then sunny, then coral as it gets close to the limit.
    static func level(_ percent: Double, base: Color) -> Color {
        switch percent {
        case ..<70: return base
        case ..<90: return sun
        default: return coral
        }
    }
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Containers

extension View {
    func card() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            )
    }
}

struct CardTitle<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(text).font(.rounded(14, .bold)).foregroundStyle(Palette.text)
            Spacer()
            trailing
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text) { EmptyView() } }
}

// MARK: - Controls

/// Round toolbar button that pops a little on hover.
struct IconButton: View {
    let systemName: String
    let help: String
    var rotation: Double = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(hovering ? Palette.blue : Palette.text2)
                .rotationEffect(.degrees(rotation))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.card))
                .scaleEffect(hovering ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3, bounce: 0.6)) { hovering = h } }
        .help(help)
    }
}

/// Segmented control whose highlight pill slides between options.
struct PillToggle: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i])
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(selection == i ? .white : Palette.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        if selection == i {
                            Capsule().fill(Palette.blue).matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { selection = i }
                    }
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.line))
    }
}

struct Chip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(Palette.text2)
            Spacer(minLength: 2)
            Text(value).fontWeight(.semibold).foregroundStyle(Palette.text).monospacedDigit()
        }
        .font(.rounded(11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - Animated pieces

/// Circle that fills with gently moving water up to `percent`.
struct LiquidBubble: View {
    let percent: Double?
    let title: String
    let subtitle: String
    let base: Color

    @State private var hovering = false
    // Fill animates from `from` to `percent`, starting at `start` (bubble creation, then each change).
    @State private var from = 0.0
    @State private var start = Date()

    private var color: Color { Palette.level(percent ?? 0, base: base) }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1 / 40)) { context in
                bubble(at: context.date)
            }
            .frame(width: 96, height: 96)
            .overlay(Circle().strokeBorder(color.opacity(0.3), lineWidth: 2))
            .scaleEffect(hovering ? 1.07 : 1)
            .onHover { h in withAnimation(.spring(duration: 0.35, bounce: 0.55)) { hovering = h } }
            .onChange(of: percent) { old, _ in
                from = old ?? 0
                start = Date()
            }

            VStack(spacing: 1) {
                Text(title).font(.rounded(13, .semibold)).foregroundStyle(Palette.text)
                Text(subtitle).font(.rounded(11)).foregroundStyle(Palette.text2)
            }
        }
    }

    private func bubble(at now: Date) -> some View {
        let progress = min(1, max(0, now.timeIntervalSince(start) / 1.4))
        let eased = 1 - pow(1 - progress, 3)
        let value = from + ((percent ?? 0) - from) * eased
        let phase = now.timeIntervalSinceReferenceDate * (hovering ? 3.2 : 1.4)
        let level = value / 100

        return ZStack {
            Circle().fill(color.opacity(0.12))
            Wave(level: level, phase: phase + 1.8, amplitude: 4.5).fill(color.opacity(0.35))
            Wave(level: level, phase: phase, amplitude: 3.5).fill(color)
            percentLabel(value).foregroundStyle(Palette.text)
            percentLabel(value).foregroundStyle(.white)
                .mask(Wave(level: level, phase: phase, amplitude: 3.5))
        }
        .clipShape(Circle())
    }

    private func percentLabel(_ value: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(percent == nil ? "–" : "\(Int(value.rounded()))").font(.rounded(26, .bold)).monospacedDigit()
            Text("%").font(.rounded(12, .bold))
        }
    }
}

struct Wave: Shape {
    var level: Double  // 0...1
    var phase: Double
    var amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }
        // Calm the wave near empty/full so it never spills past the edges.
        let calm = CGFloat(min(1, min(level, 1 - level) * 8 + 0.15))
        let amp = amplitude * calm
        let baseline = rect.maxY - rect.height * CGFloat(level)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: CGFloat(0), through: rect.width, by: 2) {
            let angle = Double(x / rect.width) * 2 * .pi * 1.2 + phase
            let y = baseline + CGFloat(sin(angle)) * amp
            path.addLine(to: CGPoint(x: rect.minX + x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Three dots hopping one after another, like someone typing.
struct BouncingDots: View {
    var color: Color = Palette.blue

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .offset(y: -abs(sin(t * 5 - Double(i) * 0.7)) * 4)
                }
            }
        }
    }
}

/// Bar chart where bars spring up one by one; hovering a bar reports its index.
struct InteractiveBars: View {
    let values: [Int]
    /// Evenly spaced axis labels; values.count should be a multiple of labels.count.
    let labels: [String]
    let current: Int
    var future: Int? = nil
    @Binding var hovered: Int?

    @State private var grown = false
    private let height: CGFloat = 60

    var body: some View {
        let maxValue = max(values.max() ?? 0, 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    bar(i, maxValue: maxValue)
                }
            }
            HStack(spacing: 3) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.rounded(9, .medium))
                        .foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: labels.count == values.count ? .center : .leading)
                }
            }
        }
        .onAppear { grown = true }
    }

    private func bar(_ i: Int, maxValue: Int) -> some View {
        let barHeight: CGFloat = values[i] > 0 ? max(5, CGFloat(values[i]) / CGFloat(maxValue) * height) : 0
        let isFuture = future.map { i >= $0 } ?? false
        return ZStack(alignment: .bottom) {
            Capsule().fill(Palette.line.opacity(isFuture ? 0.5 : 1))
            Capsule()
                .fill(color(i))
                .frame(height: grown ? barHeight : 0)
                .animation(.spring(duration: 0.7, bounce: 0.45).delay(Double(i) * 0.025), value: grown)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .scaleEffect(x: hovered == i ? 1.3 : 1, y: 1, anchor: .bottom)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.spring(duration: 0.25, bounce: 0.5)) {
                if h { hovered = i } else if hovered == i { hovered = nil }
            }
        }
    }

    private func color(_ i: Int) -> Color {
        if hovered == i { return Palette.coral }
        if i == current { return Palette.blue }
        return Palette.blue.opacity(0.35)
    }
}

/// A one-shot burst of confetti each time `trigger` changes.
struct ConfettiView: View {
    let trigger: Int

    private struct Piece {
        let vx: Double, vy: Double, spin: Double, size: CGSize, color: Color, round: Bool
    }

    @State private var start: Date?
    @State private var pieces: [Piece] = []
    private let lifetime = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            Canvas { ctx, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                guard t < lifetime else { return }
                for p in pieces {
                    let x = size.width / 2 + p.vx * t
                    let y = 60 + p.vy * t + 0.5 * 700 * t * t
                    var piece = ctx
                    piece.opacity = 1 - t / lifetime
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * t))
                    let rect = CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size)
                    piece.fill(p.round ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        pieces = (0..<60).map { _ in
            let angle = Double.random(in: -Double.pi * 0.95 ... -Double.pi * 0.05)
            let speed = Double.random(in: 180...420)
            return Piece(
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                spin: Double.random(in: -10...10),
                size: CGSize(width: Double.random(in: 5...9), height: Double.random(in: 3...6)),
                color: Palette.confetti.randomElement()!,
                round: Bool.random()
            )
        }
        start = Date()
        Task {
            try? await Task.sleep(for: .seconds(lifetime))
            start = nil
        }
    }
}

// MARK: - Menu bar

/// Drives the spinning menu bar icon while a session is working.
@MainActor
final class MenuBarAnimator: ObservableObject {
    @Published private(set) var phase = 0
    private var timer: Timer?

    func setActive(_ active: Bool) {
        if active, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 12, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.phase += 1 }
            }
        } else if !active {
            timer?.invalidate()
            timer = nil
        }
    }
}

enum MenuBarIcon {
    /// Ring that fills with the session limit.
    static func ring(fraction: Double) -> NSImage {
        draw { center, radius in
            stroke(arcFrom: 90, sweep: 360, center: center, radius: radius, alpha: 0.3)
            let f = min(max(fraction, 0), 1)
            if f > 0 { stroke(arcFrom: 90, sweep: 360 * f, center: center, radius: radius, alpha: 1) }
        }
    }

    /// Spinner: a short arc that travels around the ring.
    static func spinner(phase: Int) -> NSImage {
        draw { center, radius in
            stroke(arcFrom: 90, sweep: 360, center: center, radius: radius, alpha: 0.3)
            stroke(arcFrom: 90 - Double(phase % 12) * 30, sweep: 100, center: center, radius: radius, alpha: 1)
        }
    }

    static func done() -> NSImage {
        let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")!
        image.isTemplate = true
        return image
    }

    private static func draw(_ body: @escaping (NSPoint, CGFloat) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            body(NSPoint(x: 8, y: 8), 6.25)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func stroke(arcFrom start: Double, sweep: Double, center: NSPoint, radius: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: CGFloat(start), endAngle: CGFloat(start - sweep), clockwise: true)
        path.lineWidth = 2
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }
}
