import SwiftUI

/// Black shape that grows out of the camera notch: small outward flares at the top corners, rounded bottom.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    static func flare(for state: NotchModel.State) -> CGFloat {
        state == .closed || state == .live ? 6 : 10
    }

    static func radius(for state: NotchModel.State) -> CGFloat {
        switch state {
        case .closed, .live: return 10
        case .pop: return 22
        case .expanded: return 26
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let f = min(flare, w / 4), r = min(radius, (h - f) / 2, (w - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: f, y: f), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: f, y: h - r))
        p.addQuadCurve(to: CGPoint(x: f + r, y: h), control: CGPoint(x: f, y: h))
        p.addLine(to: CGPoint(x: w - f - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - f, y: h - r), control: CGPoint(x: w - f, y: h))
        p.addLine(to: CGPoint(x: w - f, y: f))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - f, y: 0))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var limits: PlanLimitClient
    @EnvironmentObject var usage: UsageTracker

    /// Opening: an unhurried spring that settles softly, like the Dynamic Island.
    private let openCurve = Animation.spring(response: 0.46, dampingFraction: 0.8)
    /// Closing: a touch quicker and with no bounce, so it tucks away calmly.
    private let closeCurve = Animation.spring(response: 0.36, dampingFraction: 1)

    /// Growing states use the opening curve, shrinking ones the closing curve.
    private func morph(to state: NotchModel.State) -> Animation {
        state == .closed || state == .live ? closeCurve : openCurve
    }

    var body: some View {
        let state = model.state(busy: sessions.busyCount > 0)
        let size = model.size(for: state)
        let flare = NotchShape.flare(for: state)
        let shape = NotchShape(flare: flare, radius: NotchShape.radius(for: state))

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)

                ZStack(alignment: .top) {
                    // The full app stays built (just hidden) so opening it is instant and its height is already known.
                    PopoverView(inNotch: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: NotchContentHeightKey.self, value: geo.size.height)
                        })
                        .onPreferenceChange(NotchContentHeightKey.self) { h in
                            if h > 0, abs(h - model.contentHeight) > 0.5 { model.contentHeight = h }
                        }
                        .padding(.top, model.notch.height - 8)
                        // Eases in a beat after the shape starts opening, settling down from slightly smaller.
                        .opacity(state == .expanded ? 1 : 0)
                        .scaleEffect(state == .expanded ? 1 : 0.94, anchor: .top)
                        .offset(y: state == .expanded ? 0 : -10)
                        .animation(state == .expanded ? .easeOut(duration: 0.32).delay(0.07) : .easeIn(duration: 0.14),
                                   value: state)
                        .allowsHitTesting(state == .expanded)
                        .environment(\.dragonPaused, state != .expanded)

                    if state == .live {
                        liveRow.transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    }
                    if state == .pop, let session = model.popped {
                        PopContent(session: session, notchHeight: model.notch.height)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8))
                                    .animation(.easeOut(duration: 0.3).delay(0.08)),
                                removal: .opacity.animation(.easeIn(duration: 0.14))))
                    }
                }
                .padding(.horizontal, flare)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .animation(morph(to: state), value: state)
            .animation(morph(to: state), value: size)
            Spacer(minLength: 0)
        }
        .frame(width: NotchWindowController.windowSize.width, height: NotchWindowController.windowSize.height,
               alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: model.expanded) { _, open in
            guard open else { return }
            usage.refresh()
            Task { await limits.refreshIfStale() }
        }
    }

    /// Working dot on the left of the notch, session limit on the right.
    private var liveRow: some View {
        HStack(spacing: 0) {
            DragonView(mood: .working, size: 26)
                .padding(.top, 2)
                .frame(width: 50)
            Spacer(minLength: model.notch.width)
            HStack(spacing: 4) {
                MiniRing(fraction: (limits.fiveHourPercent ?? 0) / 100)
                Text(limits.fiveHourPercent.map { "\(Int($0.rounded()))%" } ?? "")
                    .font(.app(10, .medium))
                    .foregroundStyle(Palette.text2)
                    .monospacedDigit()
            }
            .frame(width: 50)
        }
        // Exactly as wide as the live shape, so the dot and ring sit just either side of the notch.
        .frame(width: model.notch.width + 100, height: model.notch.height)
    }
}

private struct NotchContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// "Done" card that drops out of the notch when a session finishes.
private struct PopContent: View {
    let session: LiveSession
    let notchHeight: CGFloat
    @State private var checked = false

    var body: some View {
        HStack(spacing: 4) {
            // Room on the right for its fire.
            DragonView(mood: .happy, size: 44, fireRoom: 0.6)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Palette.onSilver)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Palette.silverGradient))
                        .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                        .offset(x: 30)
                }
                .scaleEffect(checked ? 1 : 0.6)
                .opacity(checked ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.displayName) finished")
                    .font(.app(13, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(session.shortFolder.isEmpty ? "Waiting for you" : session.shortFolder)
                    .font(.app(11))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { NotchWindowController.shared.jump(to: session) } label: {
                Text("Jump")
                    .font(.app(11, .medium))
                    .foregroundStyle(Palette.onSilver)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.silverGradient))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, notchHeight + 10)
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
        .onAppear { withAnimation(.snappy(duration: 0.3, extraBounce: 0.15).delay(0.08)) { checked = true } }
    }
}

/// Tiny session-limit ring for the live notch.
private struct MiniRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Palette.line, lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Palette.level(fraction * 100, base: Palette.silver),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .animation(Motion.smooth, value: fraction)
    }
}
