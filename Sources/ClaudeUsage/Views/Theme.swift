import AppKit
import SwiftUI

enum Palette {
    static let bg = Color(hex: 0x141312)
    static let surface = Color(hex: 0x1C1B19)
    static let hairline = Color.white.opacity(0.07)
    static let text = Color(hex: 0xF2EFEA)
    static let text2 = Color(hex: 0xF2EFEA).opacity(0.58)
    static let text3 = Color(hex: 0xF2EFEA).opacity(0.34)
    static let track = Color.white.opacity(0.06)
    static let accent = Color(hex: 0xD97757)
    static let sand = Color(hex: 0xCDBFA8)
    static let critical = Color(hex: 0xE5484D)

    static let series: [Color] = [accent, sand, text2, text3]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// Editorial serif (New York) for headline numbers.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static let body13 = Font.system(size: 13)
    static let small = Font.system(size: 11)
}

/// Small uppercase section label.
struct Eyebrow<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.text3)
            Spacer()
            trailing
        }
    }
}

extension Eyebrow where Trailing == EmptyView {
    init(_ text: String) {
        self.text = text
        self.trailing = EmptyView()
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.hairline).frame(height: 1) }
}

/// Toolbar icon with a soft hover state.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? Palette.text : Palette.text2)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Palette.track : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Two-option text switch with an accent underline.
struct TextSwitch: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(options[i])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selection == i ? Palette.text : Palette.text3)
                        .padding(.bottom, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selection == i ? Palette.accent : .clear).frame(height: 1.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// Dot with a slow outward ripple, used for anything that is live.
struct PulsingDot: View {
    var color: Color = Palette.accent
    var size: CGFloat = 7
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.45))
                .frame(width: size, height: size)
                .scaleEffect(animate ? 2.6 : 1)
                .opacity(animate ? 0 : 1)
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { animate = true }
        }
    }
}

/// Watch-style dial: minute-tick bezel, outer ring = session limit, inner ring = weekly limit.
struct LimitDial: View {
    let outer: Double?  // 0...100
    let inner: Double?
    var size: CGFloat = 118

    var body: some View {
        ZStack {
            Canvas { ctx, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let r = canvasSize.width / 2
                for i in 0..<60 {
                    let major = i % 5 == 0
                    let angle: CGFloat = CGFloat(i) / 60 * 2 * .pi - .pi / 2
                    let dx: CGFloat = cos(angle), dy: CGFloat = sin(angle)
                    let inner: CGFloat = r - (major ? 5 : 2.5)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + dx * inner, y: c.y + dy * inner))
                    p.addLine(to: CGPoint(x: c.x + dx * r, y: c.y + dy * r))
                    ctx.stroke(p, with: .color(.white.opacity(major ? 0.28 : 0.12)), lineWidth: 1)
                }
            }

            ring(value: outer, color: outer.map(Self.sessionColor) ?? Palette.accent, diameter: size - 20)
            ring(value: inner, color: Palette.sand, diameter: size - 40)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(outer.map { "\(Int($0.rounded()))" } ?? "–")
                        .font(.display(30))
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                    Text("%").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text3)
                }
                Text("session").font(.system(size: 9.5)).foregroundStyle(Palette.text3)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.8), value: outer)
        .animation(.spring(duration: 0.8), value: inner)
    }

    static func sessionColor(_ v: Double) -> Color { v >= 90 ? Palette.critical : Palette.accent }

    private func ring(value: Double?, color: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max((value ?? 0) / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Slim bar chart; the highlighted bar is drawn in the accent colour.
struct BarChart: View {
    let values: [Int]
    /// Evenly spaced axis labels; values.count should be a multiple of labels.count.
    let labels: [String]
    var centerLabels = false
    var highlight: Int? = nil
    var future: Int? = nil  // bars at or after this index haven't happened yet
    var tooltips: [String] = []
    var height: CGFloat = 46

    var body: some View {
        let maxValue = max(values.max() ?? 0, 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.white.opacity(0.035)).frame(height: height)
                        if values[i] > 0 {
                            Capsule()
                                .fill(color(i))
                                .frame(height: max(3, CGFloat(values[i]) / CGFloat(maxValue) * height))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .help(tooltips.indices.contains(i) ? tooltips[i] : "")
                }
            }
            HStack(spacing: 3) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: centerLabels ? .center : .leading)
                }
            }
        }
    }

    private func color(_ i: Int) -> Color {
        if i == highlight { return Palette.accent }
        if let future, i >= future { return Palette.track }
        return Palette.text.opacity(0.42)
    }
}

/// Proportional strip of each model's share of tokens.
struct ModelSplit: View {
    let models: [ModelUsage]

    var body: some View {
        let total = max(models.reduce(0) { $0 + $1.summary.total }, 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(models.prefix(4).enumerated()), id: \.element.id) { i, m in
                        Capsule()
                            .fill(Palette.series[i])
                            .frame(width: max(3, geo.size.width * CGFloat(m.summary.total) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 4)

            HStack(spacing: 14) {
                ForEach(Array(models.prefix(4).enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: 5) {
                        Circle().fill(Palette.series[i]).frame(width: 5, height: 5)
                        Text(prettyModelName(m.model)).foregroundStyle(Palette.text2)
                        Text("\(Int((Double(m.summary.total) / Double(total) * 100).rounded()))%")
                            .foregroundStyle(Palette.text3).monospacedDigit()
                    }
                    .font(.small)
                }
            }
        }
    }
}

/// Menu bar glyph: a tiny ring showing the session limit, filled centre while tasks run.
enum MenuBarIcon {
    static func image(fraction: Double, active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let center = NSPoint(x: 8, y: 8)
            let radius: CGFloat = 6.25

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.8
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            let f = min(max(fraction, 0), 1)
            if f > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                arc.lineWidth = 1.8
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            if active {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 5.25, y: 5.25, width: 5.5, height: 5.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
