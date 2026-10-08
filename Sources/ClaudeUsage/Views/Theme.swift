import AppKit
import SwiftUI

// MARK: - Colours & type

enum Palette {
    static let bg = Color.dynamic(light: 0xF6F3FF, dark: 0x120D1F)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1E1731)
    static let line = Color.dynamic(light: 0xECE6FB, dark: 0x2D2445)
    static let text = Color.dynamic(light: 0x1B1033, dark: 0xF4F0FF)
    static let text2 = Color.dynamic(light: 0x6B6285, dark: 0xADA4C7)
    static let text3 = Color.dynamic(light: 0xA9A1C2, dark: 0x6E658A)

    /// Tech purple: the main accent.
    static let purple = Color.dynamic(light: 0x7C3AED, dark: 0x9D6BFF)
    /// Cyber lime: for fills (bars, dots, badges). Too bright to read as text on white; use `limeInk` for that.
    static let lime = Color.dynamic(light: 0xB8F000, dark: 0xCCFF33)
    /// Lime that stays readable as text or icons.
    static let limeInk = Color.dynamic(light: 0x5C8A00, dark: 0xCCFF33)
    /// Text or icons placed on a lime fill.
    static let onLime = Color(nsColor: NSColor(hex: 0x1B1033))
    static let sun = Color.dynamic(light: 0xFFA412, dark: 0xFFC247)
    static let coral = Color.dynamic(light: 0xFF4D8D, dark: 0xFF6FA5)

    static let confetti: [Color] = [purple, lime, sun, coral]

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
                    .shadow(color: Palette.purple.opacity(0.08), radius: 12, y: 4)
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
                .foregroundStyle(hovering ? Palette.purple : Palette.text2)
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
    /// Stretch the segments to fill the available width (used for the main tab bar).
    var fill = false
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i])
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(selection == i ? .white : Palette.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, fill ? 6 : 4)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background {
                        if selection == i {
                            Capsule().fill(Palette.purple).matchedGeometryEffect(id: "pill", in: ns)
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

// MARK: - Gauges

/// Slim progress bar for one plan limit. It only animates when the value changes.
struct LimitBar: View {
    let title: String
    let percent: Double?
    let subtitle: String
    let base: Color

    private var value: Double { min(max(percent ?? 0, 0), 100) }
    private var color: Color { Palette.level(value, base: base) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.rounded(13, .semibold)).foregroundStyle(Palette.text)
                Text(subtitle).font(.rounded(11)).foregroundStyle(Palette.text2)
                Spacer()
                Text(percent == nil ? "–" : "\(Int(value.rounded()))%")
                    .font(.rounded(13, .bold))
                    .foregroundStyle(value < 70 ? Palette.text : color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line)
                    Capsule()
                        .fill(color)
                        .frame(width: value > 0 ? max(8, geo.size.width * value / 100) : 0)
                }
            }
            .frame(height: 8)
        }
        .animation(.snappy(duration: 0.5), value: value)
    }
}

/// Static "working" badge for a busy session row.
struct WorkingBadge: View {
    var hovering = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Palette.purple)
            .symbolEffect(.pulse, isActive: hovering)
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
        if hovered == i { return Palette.lime }
        if i == current { return Palette.purple }
        return Palette.purple.opacity(0.3)
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

enum MenuBarIcon {
    /// Ring that fills with the session limit. `dot` adds a centre dot while Claude is working.
    static func ring(fraction: Double, dot: Bool = false) -> NSImage {
        draw { center, radius in
            stroke(arcFrom: 90, sweep: 360, center: center, radius: radius, alpha: 0.3)
            let f = min(max(fraction, 0), 1)
            if f > 0 { stroke(arcFrom: 90, sweep: 360 * f, center: center, radius: radius, alpha: 1) }
            if dot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
            }
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
