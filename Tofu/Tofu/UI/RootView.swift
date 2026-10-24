import SwiftUI

/// Arc-style main window: the sidebar sits on a tinted gradient (the selected subject's hue) and the detail is an
/// inset rounded card. ⌘S hides the sidebar; it then peeks out while the pointer rests on the left edge.
/// Dragging the gap between the sidebar and the card resizes the sidebar (double-click resets it); the width is
/// remembered.
/// When model.engine.isLocked shows LockedView(model:) full-window instead.
/// Presents SessionSummaryView once a session has ended (not when it was interrupted by quitting).
struct RootView: View {
    let model: AppModel
    @State private var summary: Session?
    @State private var isAddingSubject = false
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @State private var isPeeking = false
    @AppStorage("sidebarWidth") private var storedSidebarWidth = Double(RootView.sidebarWidth)
    /// The width while the resize handle is dragged; saved to `storedSidebarWidth` when the drag ends.
    @State private var draggedSidebarWidth: CGFloat?
    @State private var dragStartWidth: CGFloat?
    @State private var isHoveringHandle = false
    @State private var isResizeCursorPushed = false
    @Environment(\.colorScheme) private var colorScheme

    /// The default sidebar width.
    static let sidebarWidth: CGFloat = 250
    /// How narrow or wide the sidebar can be dragged.
    static let sidebarWidthRange: ClosedRange<CGFloat> = 200...340

    /// `width` limited to `sidebarWidthRange`; a stored value that isn't a number falls back to the default.
    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return sidebarWidth }
        return min(max(width, sidebarWidthRange.lowerBound), sidebarWidthRange.upperBound)
    }

    private var currentSidebarWidth: CGFloat {
        draggedSidebarWidth ?? Self.clampedSidebarWidth(CGFloat(storedSidebarWidth))
    }

    var body: some View {
        Group {
            if model.engine.isLocked {
                LockedView(model: model)
            } else {
                chrome
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onChange(of: model.engine.lastEnded?.id) { _, _ in
            if let ended = model.engine.lastEnded, SessionSummaryText.shouldPresent(ended) {
                summary = ended
            }
        }
        .sheet(item: $summary) { ended in
            SessionSummaryView(model: model, session: ended)
        }
        .sheet(isPresented: Binding(get: { model.isWrappingUpDay && !model.engine.isLocked && summary == nil },
                                    set: { if !$0 { model.isWrappingUpDay = false } })) {
            EndOfDayView(model: model)
        }
    }

    // MARK: Chrome

    private var dark: Bool { colorScheme == .dark }
    private var palette: SidebarPalette { SidebarPalette.make(for: model.selection, dark: dark) }

    private var chrome: some View {
        ZStack(alignment: .topLeading) {
            palette.gradient
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: palette)
            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebar
                        .overlay(alignment: .trailing) { resizeHandle }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    if !sidebarVisible { collapsedBar }
                    card
                }
            }
            if !sidebarVisible { peek }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(shortcuts)
        .sheet(isPresented: $isAddingSubject) {
            SubjectEditorView(model: model)
        }
    }

    private var sidebar: some View {
        SidebarView(model: model, palette: palette, dark: dark,
                    onHide: { setSidebar(visible: false) },
                    onAddSubject: { isAddingSubject = true })
            .frame(width: currentSidebarWidth)
    }

    /// An invisible strip over the sidebar's trailing gutter, the gap before the card. Shows the resize cursor.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: Theme.Space.s)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                isHoveringHandle = inside
                updateResizeCursor()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? currentSidebarWidth
                        dragStartWidth = start
                        draggedSidebarWidth = Self.clampedSidebarWidth(start + value.translation.width)
                    }
                    .onEnded { _ in
                        if let draggedSidebarWidth { storedSidebarWidth = Double(draggedSidebarWidth) }
                        draggedSidebarWidth = nil
                        dragStartWidth = nil
                        updateResizeCursor()
                    }
            )
            .onTapGesture(count: 2) { storedSidebarWidth = Double(Self.sidebarWidth) }
            .accessibilityElement()
            .accessibilityLabel("Sidebar width")
            .accessibilityValue("\(Int(currentSidebarWidth)) points")
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 20 : (direction == .decrement ? -20 : 0)
                storedSidebarWidth = Double(Self.clampedSidebarWidth(currentSidebarWidth + step))
            }
    }

    /// Keeps the resize cursor while the pointer is on the handle or a drag is under way, and only pops what it pushed.
    private func updateResizeCursor() {
        let wantsCursor = isHoveringHandle || dragStartWidth != nil
        if wantsCursor && !isResizeCursorPushed {
            NSCursor.resizeLeftRight.push()
            isResizeCursorPushed = true
        } else if !wantsCursor && isResizeCursorPushed {
            NSCursor.pop()
            isResizeCursorPushed = false
        }
    }

    /// The detail on its own rounded, shadowed card, inset from the chrome like Arc's web view.
    private var card: some View {
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(dark ? 0.35 : 0.16), radius: 8, y: 2)
            .padding(.top, sidebarVisible ? Theme.Space.s : 0)
            .padding([.bottom, .trailing], Theme.Space.s)
            .padding(.leading, sidebarVisible ? 0 : Theme.Space.s)
    }

    /// With the sidebar hidden: room for the traffic lights and the button that brings the sidebar back.
    private var collapsedBar: some View {
        HStack(spacing: 2) {
            SidebarIconButton(systemImage: "sidebar.left", help: "Show sidebar (⌘S)",
                              palette: palette, dark: dark) { setSidebar(visible: true) }
            Spacer()
        }
        .padding(.leading, 76)
        .frame(height: 30)
        .padding(.bottom, 4)
        .background(WindowDragArea())
        .foregroundStyle(palette.foregroundColor)
    }

    /// A strip on the left edge; resting on it slides the sidebar out over the card until the pointer leaves.
    private var peek: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { if $0 { withAnimation(.easeOut(duration: 0.16)) { isPeeking = true } } }
            if isPeeking {
                sidebar
                    .padding(.bottom, Theme.Space.s)
                    .background(palette.gradient)
                    .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: Theme.radius,
                                                      topTrailingRadius: Theme.radius, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 15, x: 4)
                    .onHover { if !$0 { withAnimation(.easeIn(duration: 0.16)) { isPeeking = false } } }
                    .transition(.move(edge: .leading))
            }
        }
    }

    /// ⌘S toggles the sidebar and ⌘N adds a subject, whether or not the sidebar is showing.
    private var shortcuts: some View {
        ZStack {
            Button("Toggle sidebar") { setSidebar(visible: !sidebarVisible) }
                .keyboardShortcut("s", modifiers: .command)
            Button("Add subject") { isAddingSubject = true }
                .keyboardShortcut("n", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func setSidebar(visible: Bool) {
        isPeeking = false
        isHoveringHandle = false
        updateResizeCursor()
        withAnimation(.spring(duration: 0.3)) { sidebarVisible = visible }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case .today:
            TodayView(model: model)
        case .subject(let id):
            if let subject = model.subject(id: id) {
                SubjectDetailView(model: model, subject: subject)
                    .id(subject.id)
            } else {
                emptyState
            }
        case .stats:
            StatsView(model: model)
        case .connections:
            ConnectionsView(model: model)
        case .settings:
            SettingsView(model: model)
        case nil:
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Text("Pick a subject to lock in").font(.title3.weight(.semibold))
            Text(model.data.subjects.isEmpty ? "Add one with “New Subject” in the sidebar (⌘N)." : "Or open Stats and Settings.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
