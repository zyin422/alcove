import SwiftUI

/// The study buddy's face: a circle outline, two eye dots and a smile, drawn in the label color.
struct BotAvatar: View {
    var size: CGFloat = 24

    var body: some View {
        let line = max(1, size * 0.07)
        ZStack {
            Circle()
                .stroke(Color.primary, lineWidth: line)
            Circle()
                .fill(Color.primary)
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: -size * 0.16, y: -size * 0.1)
            Circle()
                .fill(Color.primary)
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(x: size * 0.16, y: -size * 0.1)
            Smile()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .frame(width: size * 0.42, height: size * 0.12)
                .offset(y: size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Upward-curving arc spanning the full width of its frame and dipping to the bottom at the middle.
    private struct Smile: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control: CGPoint(x: rect.midX, y: rect.maxY * 2 - rect.minY))
            return path
        }
    }
}
