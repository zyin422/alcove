import AppKit
import SwiftUI

/// Pure geometry for the floating companion (unit-tested).
enum CompanionLayout {
    static let portraitSize = MossView.designSize
    static let bubbleHeight: CGFloat = 100
    static let panelSize = CGSize(width: 240, height: 270)
    static let margin: CGFloat = 16
    static let bubbleWidth: CGFloat = 220

    /// Panel frame in the bottom-right corner of `visible` (Cocoa coordinates), inside `margin`.
    static func frame(size: CGSize, visible: CGRect) -> CGRect {
        CGRect(x: visible.maxX - margin - size.width, y: visible.minY + margin,
               width: size.width, height: size.height)
    }
}

/// What the companion currently shows. CompanionCenter writes it; the panel's view observes it.
@Observable @MainActor final class CompanionState {
    var expression: CompanionExpression = .calm
    /// nil hides the speech bubble.
    var bubbleText: String?
}

/// A storybook speech bubble (cream paper, brown ink, a little tail) above Moss, pinned to the panel's bottom.
struct CompanionView: View {
    let state: CompanionState

    private static let paper = Color(red: 0.99, green: 0.97, blue: 0.92)
    private static let ink = Color(red: 0.30, green: 0.24, blue: 0.18)

    var body: some View {
        VStack(spacing: 2) {
            if let text = state.bubbleText {
                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Self.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: CompanionLayout.bubbleWidth)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Self.paper)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Self.ink.opacity(0.55), lineWidth: 1.4))
                        )
                    BubbleTail()
                        .fill(Self.paper)
                        .overlay(BubbleTail().stroke(Self.ink.opacity(0.55), lineWidth: 1.4))
                        .frame(width: 16, height: 9)
                        .offset(y: -1.5)
                }
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            MossView(expression: state.expression)
                .frame(width: CompanionLayout.portraitSize.width,
                       height: CompanionLayout.portraitSize.height)
        }
        .animation(.spring(duration: 0.3), value: state.bubbleText)
        .animation(.easeInOut(duration: 0.25), value: state.expression)
        .frame(width: CompanionLayout.panelSize.width,
               height: CompanionLayout.panelSize.height, alignment: .bottom)
    }
}

/// The bubble's tail: a downward triangle whose top edge is hidden under the bubble.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Floating, non-activating companion shown bottom-right while locked in. Transparent background;
/// draggable by its body.
@MainActor final class CompanionPanel: NSPanel {
    init(state: CompanionState) {
        let size = CompanionLayout.panelSize
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // the view draws its own shadows; a rectangular panel shadow would show the frame
        let host = NSHostingView(rootView: CompanionView(state: state))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the panel bottom-right on the main screen and shows it without activating the app.
    func show() {
        if let visible = ScreenGeometry.mainVisibleFrame() {
            setFrame(CompanionLayout.frame(size: CompanionLayout.panelSize, visible: visible), display: true)
        } else {
            center()
        }
        orderFrontRegardless()
    }
}
