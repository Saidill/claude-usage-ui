import SwiftUI

/// What the dragon is up to; it follows what Claude is doing.
enum DragonMood: Equatable {
    /// Nothing running: head down, eye shut, smoke curling from its nostril.
    case sleeping
    /// Sessions open, all done: head up, eye glowing, watching.
    case idle
    /// Claude is working: leaning in and growling, embers in its jaw, eye burning brighter.
    case working
    /// A prompt just finished: rears back and roars fire.
    case happy
}

private struct DragonPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Stops the dragon's animation while it's out of sight (e.g. the notch content when the notch is closed).
    var dragonPaused: Bool {
        get { self[DragonPausedKey.self] }
        set { self[DragonPausedKey.self] = newValue }
    }
}

/// A fierce dragon head in profile (gunmetal scales, silver horns, a glowing eye), drawn and animated in a Canvas.
struct DragonView: View {
    var mood: DragonMood
    var size: CGFloat = 28
    /// Draws one fixed moment instead of animating (the self-test uses it to show each frame).
    var at: Double? = nil
    /// Extra width to the right (as a fraction of `size`) so the fire isn't cut off when it roars.
    var fireRoom: CGFloat = 0
    @Environment(\.dragonPaused) private var paused

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || at != nil)) { timeline in
            Canvas { ctx, canvasSize in
                DragonDrawing(mood: mood, t: at ?? timeline.date.timeIntervalSinceReferenceDate, detailed: size >= 26)
                    .draw(in: &ctx, side: canvasSize.height)
            }
        }
        .frame(width: size * (1 + fireRoom), height: size)
        .id(mood)
        .transition(.opacity)
        .animation(Motion.smooth, value: mood)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch mood {
        case .sleeping: return "Sleeping dragon"
        case .idle: return "Dragon, watching"
        case .working: return "Dragon, growling"
        case .happy: return "Dragon, roaring fire"
        }
    }
}

/// The drawing itself, in a unit square scaled to `side`. The dragon faces right.
private struct DragonDrawing {
    let mood: DragonMood
    let t: Double
    let detailed: Bool

    private let ember = Color(hex: 0xFFB547)
    private let flameOuter = Color(hex: 0xFF6A2B)
    private let flameCore = Color(hex: 0xFFF1C9)
    private let mouthDark = Color(hex: 0x2A0E06)

    func draw(in ctx: inout GraphicsContext, side s: CGFloat) {
        let unit = CGAffineTransform(scaleX: s, y: s)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        func shape(_ build: (inout Path) -> Void, _ transform: CGAffineTransform = .identity) -> Path {
            var path = Path()
            build(&path)
            return path.applying(transform.concatenating(unit))
        }
        func vertical(_ top: Color, _ bottom: Color, _ y0: Double = 0.1, _ y1: Double = 0.9) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: 0.5 * s, y: y0 * s),
                            endPoint: CGPoint(x: 0.5 * s, y: y1 * s))
        }
        let scales = vertical(Color(hex: 0x50565F), Color(hex: 0x17191D), 0.25, 0.85)
        let membrane = vertical(Color(hex: 0x30343B), Color(hex: 0x111215), 0.0, 0.8)
        let horn = vertical(Color(hex: 0xEDEFF2), Color(hex: 0x6E747E), 0.08, 0.45)
        let rim = vertical(.white.opacity(0.65), .white.opacity(0.04), 0.25, 0.7)
        let rimWidth = max(0.6, 0.014 * s)

        // MARK: Pose
        let breathe = sin(t * 2 * .pi / (mood == .sleeping ? 3.6 : 2.6))
        var headAngle = 0.0, headDrop = 0.0, jaw = 0.0, roar = 0.0
        var wingSpread = 1.0, eyeGlow = 0.6, eyeOpen = 1.0
        switch mood {
        case .sleeping:
            headAngle = 0.28; headDrop = 0.10; wingSpread = 0.55; eyeGlow = 0.18; eyeOpen = 0
        case .idle:
            headAngle = sin(t * 0.9) * 0.03; jaw = 0.02
            wingSpread = 1 + sin(t * 1.4) * 0.03
            eyeGlow = 0.65 + sin(t * 1.7) * 0.12
            eyeOpen = t.truncatingRemainder(dividingBy: 4.3) < 0.16 ? 0.1 : 1
        case .working:
            headAngle = -0.05 + sin(t * 6) * 0.02; jaw = 0.10 + sin(t * 5) * 0.04
            wingSpread = 1 + sin(t * 8) * 0.06
            eyeGlow = 0.85 + sin(t * 4) * 0.15
        case .happy:
            // A roar every 2.6 s: rear back, open wide, breathe fire, settle.
            let ph = t.truncatingRemainder(dividingBy: 2.6)
            let raw = ph < 0.3 ? ph / 0.3 : ph < 1.6 ? 1 : ph < 2.0 ? 1 - (ph - 1.6) / 0.4 : 0
            roar = raw * raw * (3 - 2 * raw) // smoothstep
            headAngle = -0.24 * roar; jaw = 0.04 + 0.46 * roar
            wingSpread = 1 + 0.14 * roar; eyeGlow = 1
        }
        let pivot = p(0.40, 0.70)
        let headT = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: headAngle))
            .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y + headDrop + breathe * 0.008))
        let hinge = p(0.60, 0.50)
        let jawT = CGAffineTransform(translationX: -hinge.x, y: -hinge.y)
            .concatenating(CGAffineTransform(rotationAngle: jaw))
            .concatenating(CGAffineTransform(translationX: hinge.x, y: hinge.y))
            .concatenating(headT)
        func onHead(_ point: CGPoint) -> CGPoint { point.applying(headT) }

        // MARK: Wing, behind everything
        let anchor = p(0.30, 0.74)
        let wingT = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: 0.9 + 0.1 * wingSpread, y: wingSpread))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y + breathe * 0.006))
        let wing = shape({ w in
            w.move(to: p(0.30, 0.74))
            w.addLine(to: p(0.20, 0.30))
            w.addLine(to: p(0.02, 0.06))
            w.addQuadCurve(to: p(0.09, 0.38), control: p(0.03, 0.25))
            w.addQuadCurve(to: p(0.15, 0.56), control: p(0.09, 0.49))
            w.addQuadCurve(to: p(0.24, 0.76), control: p(0.16, 0.68))
            w.closeSubpath()
        }, wingT)
        ctx.fill(wing, with: membrane)
        let bones = shape({ b in
            b.move(to: p(0.30, 0.74)); b.addLine(to: p(0.20, 0.30)); b.addLine(to: p(0.02, 0.06))
            b.move(to: p(0.20, 0.30)); b.addLine(to: p(0.09, 0.38))
            b.move(to: p(0.20, 0.30)); b.addLine(to: p(0.15, 0.56))
        }, wingT)
        ctx.stroke(bones, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: rimWidth * 0.8, lineCap: .round))

        // MARK: Neck, joined to the head wherever it is
        let skullBack = onHead(p(0.44, 0.44)), throat = onHead(p(0.56, 0.60))
        let neck = shape { n in
            n.move(to: p(0.06, 1.04))
            n.addQuadCurve(to: skullBack, control: p(0.12, 0.62))
            n.addLine(to: throat)
            n.addQuadCurve(to: p(0.50, 1.04), control: p(0.48, 0.76))
            n.closeSubpath()
        }
        ctx.fill(neck, with: scales)
        // Spines down the back of the neck.
        for u in [0.25, 0.45, 0.65, 0.85] {
            let a = p(0.06, 1.04), c = p(0.12, 0.62), b = skullBack
            let x = (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x
            let y = (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y
            let spine = shape { sp in
                sp.move(to: p(x + 0.03, y + 0.02))
                sp.addLine(to: p(x - 0.07, y - 0.04))
                sp.addLine(to: p(x - 0.01, y - 0.05))
                sp.closeSubpath()
            }
            ctx.fill(spine, with: horn)
        }
        if detailed {
            // A few scale ridges across the throat.
            for k in 0..<3 {
                let y = 0.80 + Double(k) * 0.07
                let ridge = shape { r in
                    r.move(to: p(0.22 + Double(k) * 0.02, y))
                    r.addQuadCurve(to: p(0.42 + Double(k) * 0.01, y - 0.02), control: p(0.32, y + 0.03))
                }
                ctx.stroke(ridge, with: .color(.white.opacity(0.10)), lineWidth: rimWidth * 0.7)
            }
        }
        ctx.stroke(neck, with: rim, lineWidth: rimWidth)

        // MARK: Mouth interior (shows when the jaw opens)
        if jaw > 0.04 {
            let lowerFront = p(0.85, 0.50).applying(jawT), lowerBack = p(0.60, 0.50).applying(jawT)
            let mouth = shape { m in
                m.move(to: onHead(p(0.62, 0.50)))
                m.addLine(to: onHead(p(0.87, 0.485)))
                m.addLine(to: lowerFront)
                m.addLine(to: lowerBack)
                m.closeSubpath()
            }
            ctx.fill(mouth, with: .linearGradient(Gradient(colors: [mouthDark, ember.opacity(0.9)]),
                                                 startPoint: onHead(p(0.62, 0.5)).applying(unit),
                                                 endPoint: lowerFront.applying(unit)))
        }

        // MARK: Horns, behind the skull
        for h in [((0.50, 0.33), (0.16, 0.10), (0.33, 0.15), (0.57, 0.30), (0.36, 0.24)),
                  ((0.46, 0.41), (0.22, 0.33), (0.33, 0.33), (0.49, 0.45), (0.35, 0.41))] {
            let hornPath = shape({ hp in
                hp.move(to: p(h.0.0, h.0.1))
                hp.addQuadCurve(to: p(h.1.0, h.1.1), control: p(h.2.0, h.2.1))
                hp.addQuadCurve(to: p(h.3.0, h.3.1), control: p(h.4.0, h.4.1))
                hp.closeSubpath()
            }, headT)
            ctx.fill(hornPath, with: horn)
        }

        // MARK: Head
        let head = shape({ hd in
            hd.move(to: p(0.42, 0.44))
            hd.addQuadCurve(to: p(0.46, 0.33), control: p(0.42, 0.36))
            hd.addQuadCurve(to: p(0.58, 0.28), control: p(0.50, 0.28))
            hd.addLine(to: p(0.66, 0.30))
            hd.addQuadCurve(to: p(0.82, 0.37), control: p(0.73, 0.31))
            hd.addLine(to: p(0.90, 0.415))
            hd.addQuadCurve(to: p(0.91, 0.455), control: p(0.918, 0.43))
            hd.addLine(to: p(0.87, 0.485))
            hd.addLine(to: p(0.62, 0.50))
            hd.addQuadCurve(to: p(0.56, 0.56), control: p(0.58, 0.53))
            hd.addQuadCurve(to: p(0.42, 0.44), control: p(0.48, 0.54))
            hd.closeSubpath()
        }, headT)
        ctx.fill(head, with: scales)
        ctx.stroke(head, with: rim, lineWidth: rimWidth)

        // Upper fangs, hanging from the lip.
        for (x, len) in [(0.70, 0.022), (0.76, 0.022), (0.84, 0.042)] {
            let y = 0.50 - (x - 0.62) / 0.25 * 0.015
            let tooth = shape({ tp in
                tp.move(to: p(x - 0.012, y - 0.004))
                tp.addLine(to: p(x, y + len))
                tp.addLine(to: p(x + 0.012, y - 0.004))
                tp.closeSubpath()
            }, headT)
            ctx.fill(tooth, with: .color(Color(hex: 0xF2F3F5)))
        }

        // Lower jaw, with teeth pointing up.
        let lowerJaw = shape({ j in
            j.move(to: p(0.60, 0.50))
            j.addLine(to: p(0.85, 0.50))
            j.addQuadCurve(to: p(0.84, 0.535), control: p(0.86, 0.52))
            j.addLine(to: p(0.66, 0.57))
            j.addLine(to: p(0.58, 0.555))
            j.closeSubpath()
        }, jawT)
        if jaw > 0.04 {
            for (x, len) in [(0.71, 0.018), (0.80, 0.028)] {
                let tooth = shape({ tp in
                    tp.move(to: p(x - 0.01, 0.502))
                    tp.addLine(to: p(x, 0.502 - len))
                    tp.addLine(to: p(x + 0.01, 0.502))
                    tp.closeSubpath()
                }, jawT)
                ctx.fill(tooth, with: .color(Color(hex: 0xF2F3F5)))
            }
        }
        ctx.fill(lowerJaw, with: scales)
        ctx.stroke(lowerJaw, with: .color(.white.opacity(0.18)), lineWidth: rimWidth * 0.8)

        // Jaw spike and nostril.
        let jawSpike = shape({ sp in
            sp.move(to: p(0.58, 0.54)); sp.addLine(to: p(0.49, 0.60)); sp.addLine(to: p(0.56, 0.57)); sp.closeSubpath()
        }, headT)
        ctx.fill(jawSpike, with: horn)
        let nostril = shape({ n in
            n.move(to: p(0.865, 0.418)); n.addQuadCurve(to: p(0.89, 0.433), control: p(0.88, 0.415))
        }, headT)
        ctx.stroke(nostril, with: .color(.black.opacity(0.8)), style: StrokeStyle(lineWidth: rimWidth, lineCap: .round))

        // MARK: Eye: an angry brow over a glowing slit
        let eyeCenter = onHead(p(0.68, 0.36))
        var glow = ctx
        glow.addFilter(.blur(radius: 0.05 * s))
        glow.opacity = eyeGlow
        let g = 0.09
        glow.fill(Path(ellipseIn: CGRect(x: (eyeCenter.x - g / 2) * s, y: (eyeCenter.y - g / 2) * s, width: g * s, height: g * s)),
                  with: .color(ember))
        if eyeOpen > 0.5 {
            let eye = shape({ e in
                e.move(to: p(0.645, 0.362))
                e.addQuadCurve(to: p(0.718, 0.356), control: p(0.68, 0.334))
                e.addQuadCurve(to: p(0.645, 0.362), control: p(0.68, 0.382))
                e.closeSubpath()
            }, headT)
            ctx.fill(eye, with: .linearGradient(Gradient(colors: [flameCore, ember]),
                                               startPoint: onHead(p(0.66, 0.35)).applying(unit),
                                               endPoint: onHead(p(0.70, 0.37)).applying(unit)))
            let slit = shape({ sl in
                sl.addEllipse(in: CGRect(x: 0.678, y: 0.344, width: 0.009, height: 0.028))
            }, headT)
            ctx.fill(slit, with: .color(.black))
        } else {
            let lid = shape({ l in
                l.move(to: p(0.645, 0.362)); l.addQuadCurve(to: p(0.718, 0.356), control: p(0.68, 0.372))
            }, headT)
            ctx.stroke(lid, with: .color(ember.opacity(0.7)), style: StrokeStyle(lineWidth: rimWidth, lineCap: .round))
        }
        let brow = shape({ b in
            b.move(to: p(0.60, 0.305)); b.addLine(to: p(0.74, 0.345))
        }, headT)
        ctx.stroke(brow, with: .color(Color(hex: 0xC9CDD3)), style: StrokeStyle(lineWidth: rimWidth * 1.5, lineCap: .round))

        // MARK: Breath
        let nose = onHead(p(0.905, 0.42))
        if mood == .sleeping || mood == .idle {
            // Smoke curling up from the nostril.
            let count = mood == .sleeping ? 3 : 2
            for i in 0..<count {
                let phase = (t * (mood == .sleeping ? 0.3 : 0.22) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                let c = CGPoint(x: nose.x + sin(phase * 5 + Double(i)) * 0.03 + phase * 0.05, y: nose.y - phase * 0.32)
                let d = 0.035 + phase * 0.07
                var puff = ctx
                puff.addFilter(.blur(radius: (0.012 + phase * 0.02) * s))
                puff.opacity = sin(phase * .pi) * 0.55
                puff.fill(Path(ellipseIn: CGRect(x: (c.x - d / 2) * s, y: (c.y - d / 2) * s, width: d * s, height: d * s)),
                          with: .color(Color(hex: 0xA9AEB6)))
            }
        }
        if mood == .working || roar > 0.05 {
            // Embers drifting up from the jaw.
            for i in 0..<4 {
                let phase = (t * 0.7 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                let c = CGPoint(x: nose.x - 0.06 + sin(phase * 7 + Double(i) * 2) * 0.05 + phase * 0.06,
                                y: nose.y + 0.06 - phase * 0.40)
                let d = 0.018 * (1 - phase * 0.5)
                var spark = ctx
                spark.opacity = sin(phase * .pi)
                spark.fill(Path(ellipseIn: CGRect(x: (c.x - d / 2) * s, y: (c.y - d / 2) * s, width: d * s, height: d * s)),
                           with: .color(i % 2 == 0 ? ember : flameOuter))
            }
        }
        if roar > 0.25 {
            // Fire: three layered tongues of flame, flickering, along the line of the snout.
            let mouthFront = onHead(p(0.88, 0.50))
            var fire = ctx
            fire.translateBy(x: mouthFront.x * s, y: mouthFront.y * s)
            fire.rotate(by: .radians(headAngle + jaw * 0.35))
            let strength = (roar - 0.25) / 0.75
            for (layer, color) in [(1.0, flameOuter), (0.72, ember), (0.42, flameCore)].enumerated().map({ ($0.element.0, $0.element.1) }) {
                let flicker = 0.85 + 0.15 * sin(t * 24 + layer * 9)
                let length = 0.55 * strength * flicker * layer * s
                let width = 0.13 * strength * flicker * layer * s
                var tongue = Path()
                tongue.move(to: .zero)
                tongue.addQuadCurve(to: CGPoint(x: length, y: sin(t * 13 + layer) * width * 0.25),
                                    control: CGPoint(x: length * 0.45, y: -width))
                tongue.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.45, y: width))
                var f = fire
                if layer == 1.0 { f.addFilter(.shadow(color: flameOuter.opacity(0.8), radius: 0.06 * s)) }
                f.fill(tongue, with: .color(color))
            }
        }
    }
}
