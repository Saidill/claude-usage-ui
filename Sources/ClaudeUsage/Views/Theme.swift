import AppKit
import SwiftUI

// MARK: - Colours & type

/// Black, silver and glass. Always dark, whatever the system appearance.
enum Palette {
    /// Black tint laid over the blurred window background.
    static let bg = Color.black.opacity(0.62)
    /// Card fill: a faint sheet of glass.
    static let glass = Color.white.opacity(0.045)
    /// Row highlight inside a card.
    static let hover = Color.white.opacity(0.07)
    static let line = Color.white.opacity(0.10)
    static let text = Color(hex: 0xF2F2F4)
    static let text2 = Color(hex: 0x9A9AA2)
    static let text3 = Color(hex: 0x5E5E66)

    /// The main accent.
    static let silver = Color(hex: 0xD4D7DD)
    /// A darker, cooler second accent.
    static let steel = Color(hex: 0x8E949E)
    /// Text or icons placed on a silver fill.
    static let onSilver = Color(hex: 0x111114)
    static let amber = Color(hex: 0xE3B26A)
    static let rose = Color(hex: 0xE07A72)

    /// Polished-metal fill for bars and the selected tab.
    static let silverGradient = LinearGradient(colors: [Color(hex: 0xFAFAFC), Color(hex: 0xA7ACB4)],
                                               startPoint: .top, endPoint: .bottom)
    /// Hairline edge that catches light at the top, like the rim of a glass pane.
    static let rim = LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom)

    static let confetti: [Color] = [.white, silver, steel, Color(hex: 0xB9BEC6)]

    /// Base colour while usage is comfortable, then amber, then rose as it gets close to the limit.
    static func level(_ percent: Double, base: Color) -> Color {
        switch percent {
        case ..<70: return base
        case ..<90: return amber
        default: return rose
        }
    }
}

/// One set of curves so everything moves the same calm way.
enum Motion {
    static let smooth = Animation.smooth(duration: 0.28)
    static let quick = Animation.snappy(duration: 0.18, extraBounce: 0)
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
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
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Containers

/// Frosted glass behind the whole window.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    func card() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.glass)
                    .strokeBorder(Palette.rim, lineWidth: 1)
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
            Text(text.uppercased())
                .font(.app(10.5, .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.text2)
            Spacer()
            trailing
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text) { EmptyView() } }
}

// MARK: - Controls

/// Round glass toolbar button that brightens on hover.
struct IconButton: View {
    let systemName: String
    let help: String
    var rotation: Double = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Palette.text : Palette.text2)
                .rotationEffect(.degrees(rotation))
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? Palette.hover : Palette.glass))
                .overlay(Circle().strokeBorder(Palette.rim, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .help(help)
    }
}

/// Segmented control whose silver pill glides between options.
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
                    .font(.app(11, .medium))
                    .foregroundStyle(selection == i ? Palette.onSilver : Palette.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, fill ? 6 : 4)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background {
                        if selection == i {
                            Capsule().fill(Palette.silverGradient).matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(Motion.smooth) { selection = i } }
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.glass))
        .overlay(Capsule().strokeBorder(Palette.rim, lineWidth: 1))
    }
}

struct Chip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(Palette.text2)
            Spacer(minLength: 2)
            Text(value).fontWeight(.medium).foregroundStyle(Palette.text).monospacedDigit()
        }
        .font(.app(11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.glass))
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

// MARK: - Gauges

/// Slim progress bar for one plan limit. It glides when the value changes and shimmers while refreshing.
struct LimitBar: View {
    let title: String
    let percent: Double?
    let subtitle: String
    var shimmering = false

    private var value: Double { min(max(percent ?? 0, 0), 100) }
    private var warning: Color? { value < 70 ? nil : Palette.level(value, base: Palette.silver) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.app(13, .medium)).foregroundStyle(Palette.text)
                Text(subtitle).font(.app(11)).foregroundStyle(Palette.text3)
                Spacer()
                Text(percent == nil ? "–" : "\(Int(value.rounded()))%")
                    .font(.app(15, .light))
                    .foregroundStyle(warning ?? Palette.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line)
                    Group {
                        if let warning { Capsule().fill(warning) } else { Capsule().fill(Palette.silverGradient) }
                    }
                    .frame(width: value > 0 ? max(6, geo.size.width * value / 100) : 0)
                    .overlay { if shimmering { Shimmer().clipShape(Capsule()) } }
                }
            }
            .frame(height: 6)
        }
        .animation(Motion.smooth, value: value)
    }
}

/// A soft band of light that sweeps across its container.
private struct Shimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: phase * geo.size.width * 1.6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

/// "Working" badge for a busy session row: a slowly breathing ellipsis.
struct WorkingBadge: View {
    var hovering = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.silver)
            .symbolEffect(.pulse, isActive: true)
    }
}

/// Bar chart whose bars rise in one by one; hovering a bar reports its index.
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
                        .font(.app(9, .medium))
                        .foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: labels.count == values.count ? .center : .leading)
                }
            }
        }
        .onAppear { grown = true }
    }

    private func bar(_ i: Int, maxValue: Int) -> some View {
        let barHeight: CGFloat = values[i] > 0 ? max(4, CGFloat(values[i]) / CGFloat(maxValue) * height) : 0
        let isFuture = future.map { i >= $0 } ?? false
        return ZStack(alignment: .bottom) {
            Capsule().fill(Palette.line.opacity(isFuture ? 0.4 : 0.8))
            Capsule()
                .fill(color(i))
                .frame(height: grown ? barHeight : 0)
                .animation(.smooth(duration: 0.4).delay(Double(i) * 0.008), value: grown)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(Motion.quick) {
                if h { hovered = i } else if hovered == i { hovered = nil }
            }
        }
    }

    private func color(_ i: Int) -> AnyShapeStyle {
        if hovered == i { return AnyShapeStyle(Color.white) }
        if i == current { return AnyShapeStyle(Palette.silverGradient) }
        return AnyShapeStyle(Palette.steel.opacity(0.35))
    }
}

/// A gentle shower of silver flakes each time `trigger` changes.
struct ConfettiView: View {
    let trigger: Int

    private struct Piece {
        let vx: Double, vy: Double, spin: Double, size: CGSize, color: Color, round: Bool
    }

    @State private var start: Date?
    @State private var pieces: [Piece] = []
    private let lifetime = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            Canvas { ctx, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                guard t < lifetime else { return }
                for p in pieces {
                    let x = size.width / 2 + p.vx * t
                    let y = 50 + p.vy * t + 0.5 * 320 * t * t
                    var piece = ctx
                    // Fade in quickly, then out slowly.
                    piece.opacity = min(t / 0.2, 1) * (1 - t / lifetime)
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
        pieces = (0..<30).map { _ in
            let angle = Double.random(in: -Double.pi * 0.9 ... -Double.pi * 0.1)
            let speed = Double.random(in: 90...220)
            return Piece(
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                spin: Double.random(in: -4...4),
                size: CGSize(width: Double.random(in: 3...6), height: Double.random(in: 2...4)),
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
