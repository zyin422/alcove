import AppKit
import SwiftUI

/// Where the companion's portrait images live. The user drops `neutral.png`, `annoyed.png`,
/// `pleased.png` and `dark.png` there (e.g. their favorite character); missing files fall back
/// to the bundled Emilia art, then the built-in drawn portrait.
enum CompanionArt {
    /// ~/Library/Application Support/Tofu/companion
    static func imagesDirectory() -> URL {
        Store.defaultURL().deletingLastPathComponent().appendingPathComponent("companion", isDirectory: true)
    }

    /// Creates the folder so Settings can open it in Finder.
    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: imagesDirectory(), withIntermediateDirectories: true)
    }

    /// Custom PNGs override the bundled portrait independently for each expression.
    static func image(for expression: CompanionExpression, directory: URL = imagesDirectory()) -> NSImage? {
        NSImage(contentsOf: directory.appendingPathComponent("\(expression.rawValue).png"))
            ?? bundledImage(for: expression)
    }

    static func bundledImage(for expression: CompanionExpression) -> NSImage? {
        NSImage(named: "Companion-\(expression.rawValue)")
    }
}

/// The companion's face: custom PNG, bundled Emilia art, or the drawn fallback.
struct CompanionPortrait: View {
    let expression: CompanionExpression

    var body: some View {
        if let image = CompanionArt.image(for: expression) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            DrawnCompanion(expression: expression)
        }
    }
}

/// Built-in fallback portrait: a silver-haired, purple-eyed anime girl drawn in SwiftUI.
/// Designed in a 150x190 space and scaled to fit its frame.
struct DrawnCompanion: View {
    let expression: CompanionExpression

    private let hair = Color(red: 0.86, green: 0.87, blue: 0.93)
    private let hairShade = Color(red: 0.76, green: 0.77, blue: 0.87)
    private let skin = Color(red: 1.0, green: 0.91, blue: 0.86)
    private let iris = Color(red: 0.56, green: 0.42, blue: 0.86)
    private let dress = Color(red: 0.33, green: 0.30, blue: 0.48)
    private let lineColor = Color(red: 0.25, green: 0.22, blue: 0.32)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 150, geo.size.height / 190)
            ZStack {
                backHair
                shoulders
                face
                bangs
                flower
                eyes
                mouth
                if expression == .annoyed || expression == .pleased { blush }
                if expression == .dark { darkAura }
            }
            .frame(width: 150, height: 190)
            .scaleEffect(s, anchor: .center)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private var backHair: some View {
        ZStack {
            // Long hair falling behind the shoulders.
            RoundedRectangle(cornerRadius: 34)
                .fill(hairShade)
                .frame(width: 104, height: 150)
                .offset(y: 12)
            Ellipse()
                .fill(hair)
                .frame(width: 100, height: 96)
                .offset(y: -40)
        }
    }

    private var shoulders: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(dress)
            .frame(width: 96, height: 42)
            .offset(y: 72)
    }

    private var face: some View {
        Ellipse()
            .fill(skin)
            .frame(width: 74, height: 80)
            .offset(y: -28)
    }

    private var bangs: some View {
        ZStack {
            // Three rounded strands across the forehead, middle one lowest.
            Ellipse().fill(hair).frame(width: 34, height: 34).offset(x: -24, y: -58)
            Ellipse().fill(hair).frame(width: 36, height: 40).offset(y: -60)
            Ellipse().fill(hair).frame(width: 34, height: 34).offset(x: 24, y: -58)
            // Side strands framing the face.
            Capsule().fill(hair).frame(width: 14, height: 66).offset(x: -40, y: -24)
            Capsule().fill(hair).frame(width: 14, height: 66).offset(x: 40, y: -24)
        }
    }

    private var flower: some View {
        // Small white flower tucked in the hair, top-left.
        ZStack {
            ForEach(0..<5, id: \.self) { petal in
                Ellipse()
                    .fill(.white)
                    .frame(width: 7, height: 11)
                    .rotationEffect(.degrees(Double(petal) * 72))
            }
            Circle().fill(Color(red: 0.95, green: 0.78, blue: 0.86)).frame(width: 5, height: 5)
        }
        .offset(x: -30, y: -70)
    }

    @ViewBuilder private var eyes: some View {
        switch expression {
        case .pleased:
            // Closed happy arcs.
            HappyEye().stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 16, height: 8).offset(x: -16, y: -32)
            HappyEye().stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 16, height: 8).offset(x: 16, y: -32)
        case .annoyed:
            openEye(at: -16, lidded: true)
            openEye(at: 16, lidded: true)
            // Brows angled in.
            brow(at: -16, angle: 18)
            brow(at: 16, angle: -18)
        case .dark:
            openEye(at: -16, irisScale: 0.6)
            openEye(at: 16, irisScale: 0.6)
        case .neutral:
            openEye(at: -16)
            openEye(at: 16)
        }
    }

    private func openEye(at x: CGFloat, lidded: Bool = false, irisScale: CGFloat = 1) -> some View {
        ZStack {
            Ellipse().fill(.white).frame(width: 17, height: lidded ? 11 : 15)
            Circle().fill(iris).frame(width: 11 * irisScale, height: 11 * irisScale)
            Circle().fill(lineColor).frame(width: 5 * irisScale, height: 5 * irisScale)
            Circle().fill(.white).frame(width: 3, height: 3).offset(x: 2, y: -2)
        }
        .offset(x: x, y: -32)
    }

    private func brow(at x: CGFloat, angle: Double) -> some View {
        Capsule()
            .fill(lineColor)
            .frame(width: 15, height: 2.5)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: -44)
    }

    @ViewBuilder private var mouth: some View {
        switch expression {
        case .pleased:
            SmileCurve().stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 7).offset(y: -12)
        case .annoyed:
            SmileCurve().stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 12, height: 5).rotationEffect(.degrees(180)).offset(y: -11)
        case .dark:
            Capsule().fill(lineColor).frame(width: 10, height: 2).offset(y: -12)
        case .neutral:
            SmileCurve().stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 12, height: 4).offset(y: -12)
        }
    }

    private var blush: some View {
        Group {
            Ellipse().fill(Color(red: 1.0, green: 0.65, blue: 0.68).opacity(0.5))
                .frame(width: 12, height: 6).offset(x: -24, y: -20)
            Ellipse().fill(Color(red: 1.0, green: 0.65, blue: 0.68).opacity(0.5))
                .frame(width: 12, height: 6).offset(x: 24, y: -20)
        }
    }

    private var darkAura: some View {
        // Shadow over the top of the face: the yandere look.
        LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: 74, height: 42)
            .clipShape(Ellipse().scale(x: 1, y: 2, anchor: .top))
            .offset(y: -57)
            .blendMode(.multiply)
    }

    /// Upward arc: a closed, happy anime eye (^).
    private struct HappyEye: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
            return path
        }
    }

    /// Downward-dipping arc for the mouth.
    private struct SmileCurve: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control: CGPoint(x: rect.midX, y: rect.maxY * 2 - rect.minY))
            return path
        }
    }
}
