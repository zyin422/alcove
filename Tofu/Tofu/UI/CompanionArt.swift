import SwiftUI

/// Moss, the study companion: a small, round forest spirit with a sprout on its head, drawn in SwiftUI in a soft,
/// hand-painted storybook style (cream body, sketchy brown outline, moss and leaves). It breathes, its leaf sways
/// and it blinks; with Reduce Motion it holds still. Designed in a 140x150 space and scaled to fit its frame.
struct MossView: View {
    let expression: CompanionExpression
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let designSize = CGSize(width: 140, height: 150)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.designSize.width, geo.size.height / Self.designSize.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                MossFigure(expression: expression, pose: MossPose(time: t))
                    .frame(width: Self.designSize.width, height: Self.designSize.height)
                    .scaleEffect(scale)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Moss, your study companion, looks \(expression.rawValue)")
    }
}

/// Where the idle animation is at a moment in time. Pure, so the motion is easy to reason about.
struct MossPose: Equatable {
    /// -1...1, one breath every 3.2 s.
    var breath: Double
    /// Degrees the sprout leans.
    var sway: Double
    /// True for 0.14 s every 4.2 s.
    var isBlinking: Bool

    init(time: TimeInterval) {
        breath = sin(time * 2 * .pi / 3.2)
        sway = 7 * sin(time * 2 * .pi / 2.6)
        isBlinking = time > 0 && time.truncatingRemainder(dividingBy: 4.2) < 0.14
    }
}

private enum MossPalette {
    static let body = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let bodyShade = Color(red: 0.92, green: 0.88, blue: 0.79)
    static let line = Color(red: 0.36, green: 0.29, blue: 0.22)
    static let moss = Color(red: 0.49, green: 0.62, blue: 0.40)
    static let mossLight = Color(red: 0.62, green: 0.74, blue: 0.48)
    static let leaf = Color(red: 0.43, green: 0.60, blue: 0.36)
    static let leafVein = Color(red: 0.32, green: 0.46, blue: 0.27)
    static let cheek = Color(red: 0.95, green: 0.62, blue: 0.58)
    static let mouth = Color(red: 0.55, green: 0.27, blue: 0.24)
}

private struct MossFigure: View {
    let expression: CompanionExpression
    let pose: MossPose

    var body: some View {
        ZStack {
            // Soft ground shadow.
            Ellipse()
                .fill(Color.black.opacity(0.13))
                .frame(width: 78 - 4 * pose.breath, height: 11)
                .blur(radius: 2.5)
                .position(x: 70, y: 141)

            ZStack {
                feet
                arms
                bodyShape
                mossPatch
                sprout
                face
            }
            .offset(y: -2 * pose.breath)
            .scaleEffect(x: 1 - 0.012 * pose.breath, y: 1 + 0.022 * pose.breath, anchor: .bottom)

            if expression == .sleepy { sleepyZ }
            if expression == .happy { sparkles }
        }
    }

    // MARK: Body

    private var bodyShape: some View {
        let shape = Ellipse().path(in: CGRect(x: 20, y: 42, width: 100, height: 94))
        return ZStack {
            shape.fill(LinearGradient(colors: [MossPalette.body, MossPalette.bodyShade],
                                      startPoint: .top, endPoint: .bottom))
            // A painted highlight, top-left.
            Ellipse()
                .fill(Color.white.opacity(0.55))
                .frame(width: 30, height: 18)
                .rotationEffect(.degrees(-25))
                .position(x: 48, y: 62)
                .blur(radius: 3)
            // Two offset strokes read as a hand-drawn line.
            shape.stroke(MossPalette.line, lineWidth: 2.2)
            shape.offsetBy(dx: 0.8, dy: 0.6).stroke(MossPalette.line.opacity(0.35), lineWidth: 1)
        }
    }

    private var feet: some View {
        ZStack {
            foot.position(x: 52, y: 134)
            foot.position(x: 88, y: 134)
        }
    }

    private var foot: some View {
        Ellipse()
            .fill(MossPalette.bodyShade)
            .overlay(Ellipse().stroke(MossPalette.line, lineWidth: 1.8))
            .frame(width: 18, height: 10)
    }

    private var arms: some View {
        let lift = expression == .happy ? -10.0 : 0
        return ZStack {
            arm.rotationEffect(.degrees(25 + lift * 2)).position(x: 22, y: 96 + lift)
            arm.rotationEffect(.degrees(-25 - lift * 2)).position(x: 118, y: 96 + lift)
        }
    }

    private var arm: some View {
        Capsule()
            .fill(MossPalette.body)
            .overlay(Capsule().stroke(MossPalette.line, lineWidth: 1.8))
            .frame(width: 12, height: 20)
    }

    private var mossPatch: some View {
        ZStack {
            ForEach(Self.mossTufts, id: \.self) { tuft in
                Circle()
                    .fill(tuft.light ? MossPalette.mossLight : MossPalette.moss)
                    .frame(width: tuft.size, height: tuft.size)
                    .position(x: tuft.x, y: tuft.y)
            }
        }
    }

    private struct Tuft: Hashable {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var light: Bool
    }

    private static let mossTufts: [Tuft] = [
        Tuft(x: 52, y: 50, size: 12, light: false), Tuft(x: 62, y: 45, size: 14, light: true),
        Tuft(x: 74, y: 44, size: 15, light: false), Tuft(x: 86, y: 48, size: 12, light: true),
        Tuft(x: 94, y: 53, size: 9, light: false), Tuft(x: 45, y: 56, size: 8, light: true),
        Tuft(x: 68, y: 50, size: 10, light: false), Tuft(x: 80, y: 52, size: 9, light: false),
    ]

    private var sprout: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 70, y: 44))
                path.addQuadCurve(to: CGPoint(x: 71, y: 20), control: CGPoint(x: 66, y: 32))
            }
            .stroke(MossPalette.leafVein, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            leaf.rotationEffect(.degrees(-38), anchor: .bottomTrailing)
                .frame(width: 22, height: 11)
                .position(x: 60, y: 19)
            leaf.rotationEffect(.degrees(28), anchor: .bottomLeading)
                .frame(width: 24, height: 12)
                .position(x: 83, y: 17)
        }
        .rotationEffect(.degrees(pose.sway), anchor: UnitPoint(x: 0.5, y: 44 / 150))
    }

    private var leaf: some View {
        ZStack {
            Ellipse().fill(MossPalette.leaf)
            Ellipse().stroke(MossPalette.leafVein, lineWidth: 1.2)
            Capsule().fill(MossPalette.leafVein.opacity(0.6)).frame(height: 1)
        }
    }

    // MARK: Face

    private var face: some View {
        ZStack {
            cheeks
            eyes
            if expression == .worried { brows }
            mouth
        }
    }

    private var cheeks: some View {
        ZStack {
            Ellipse().fill(MossPalette.cheek.opacity(expression == .happy ? 0.7 : 0.5))
                .frame(width: 13, height: 7).position(x: 42, y: 100)
            Ellipse().fill(MossPalette.cheek.opacity(expression == .happy ? 0.7 : 0.5))
                .frame(width: 13, height: 7).position(x: 98, y: 100)
        }
    }

    @ViewBuilder private var eyes: some View {
        switch expression {
        case .happy:
            ZStack {
                happyEye.position(x: 55, y: 88)
                happyEye.position(x: 85, y: 88)
            }
        case .sleepy:
            ZStack {
                sleepyEye.position(x: 55, y: 90)
                sleepyEye.position(x: 85, y: 90)
            }
        case .calm, .worried:
            ZStack {
                dotEye.position(x: 55, y: 89)
                dotEye.position(x: 85, y: 89)
            }
        }
    }

    private var dotEye: some View {
        ZStack {
            Ellipse().fill(MossPalette.line).frame(width: 8, height: 10)
            Circle().fill(Color.white).frame(width: 3, height: 3).offset(x: -1.5, y: -2)
        }
        .scaleEffect(x: 1, y: pose.isBlinking ? 0.12 : 1)
    }

    private var happyEye: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 6))
            path.addQuadCurve(to: CGPoint(x: 12, y: 6), control: CGPoint(x: 6, y: -3))
        }
        .stroke(MossPalette.line, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        .frame(width: 12, height: 8)
    }

    private var sleepyEye: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 1))
            path.addQuadCurve(to: CGPoint(x: 12, y: 1), control: CGPoint(x: 6, y: 6))
        }
        .stroke(MossPalette.line, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .frame(width: 12, height: 6)
    }

    private var brows: some View {
        ZStack {
            Capsule().fill(MossPalette.line).frame(width: 10, height: 2)
                .rotationEffect(.degrees(-16)).position(x: 54, y: 77)
            Capsule().fill(MossPalette.line).frame(width: 10, height: 2)
                .rotationEffect(.degrees(16)).position(x: 86, y: 77)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch expression {
        case .happy:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 14, y: 0), control: CGPoint(x: 7, y: 13))
                path.closeSubpath()
            }
            .fill(MossPalette.mouth)
            .overlay(Ellipse().fill(MossPalette.cheek).frame(width: 6, height: 3).offset(y: 2.5))
            .frame(width: 14, height: 8)
            .position(x: 70, y: 103)
        case .worried:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3))
                path.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 4, y: -1), control2: CGPoint(x: 8, y: 7))
            }
            .stroke(MossPalette.line, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 12, height: 6)
            .position(x: 70, y: 103)
        case .sleepy:
            Ellipse().stroke(MossPalette.line, lineWidth: 1.6)
                .frame(width: 5, height: 6)
                .position(x: 70, y: 103)
        case .calm:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 5))
            }
            .stroke(MossPalette.line, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 10, height: 4)
            .position(x: 70, y: 102)
        }
    }

    // MARK: Extras

    private var sleepyZ: some View {
        let drift = (pose.breath + 1) / 2
        return ZStack {
            Text("z").font(.system(size: 11, weight: .semibold, design: .rounded))
                .position(x: 112, y: 46 - 4 * drift)
            Text("z").font(.system(size: 15, weight: .semibold, design: .rounded))
                .position(x: 122, y: 30 - 6 * drift)
        }
        .foregroundStyle(MossPalette.line.opacity(0.6))
    }

    private var sparkles: some View {
        let twinkle = 0.6 + 0.4 * abs(pose.breath)
        return ZStack {
            Image(systemName: "sparkle").font(.system(size: 10)).position(x: 18, y: 58)
            Image(systemName: "sparkle").font(.system(size: 7)).position(x: 124, y: 66)
            Image(systemName: "sparkle").font(.system(size: 8)).position(x: 112, y: 36)
        }
        .foregroundStyle(Color(red: 0.93, green: 0.76, blue: 0.36))
        .opacity(twinkle)
    }
}

#Preview {
    HStack {
        ForEach(CompanionExpression.allCases, id: \.self) { expression in
            MossView(expression: expression).frame(width: 140, height: 150)
        }
    }
    .padding()
}
