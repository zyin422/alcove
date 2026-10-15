import AppKit
import SwiftUI

/// Pure geometry for the floating companion (unit-tested).
enum CompanionLayout {
    static let portraitSize = CGSize(width: 150, height: 190)
    static let bubbleHeight: CGFloat = 100
    static let panelSize = CGSize(width: 240, height: 300)
    static let margin: CGFloat = 16

    /// Panel frame in the bottom-right corner of `visible` (Cocoa coordinates), inside `margin`.
    static func frame(size: CGSize, visible: CGRect) -> CGRect {
        CGRect(x: visible.maxX - margin - size.width, y: visible.minY + margin,
               width: size.width, height: size.height)
    }
}

/// What the companion currently shows. CompanionCenter writes it; the panel's view observes it.
@Observable @MainActor final class CompanionState {
    var expression: CompanionExpression = .neutral
    /// nil hides the speech bubble.
    var bubbleText: String?
}

/// Speech bubble (when she's talking) above the portrait, pinned to the panel's bottom.
struct CompanionView: View {
    let state: CompanionState

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            if let text = state.bubbleText {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary))
                    .shadow(radius: 4, y: 2)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            CompanionPortrait(expression: state.expression)
                .frame(width: CompanionLayout.portraitSize.width,
                       height: CompanionLayout.portraitSize.height)
                .shadow(radius: 6, y: 3)
        }
        .animation(.easeInOut(duration: 0.2), value: state.bubbleText)
        .frame(width: CompanionLayout.panelSize.width,
               height: CompanionLayout.panelSize.height, alignment: .bottom)
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
