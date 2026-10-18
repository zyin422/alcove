import AppKit

/// Live WindowPresenting: moves the main window into the app zone (thirds / 70-30) or swaps it for the
/// floating MiniTimerPanel (split / full), and puts everything back when the session ends.
@MainActor final class MainWindowPresenter: WindowPresenting {
    private let model: AppModel
    /// The main window as found at lock-in. Kept because an ordered-out window is invisible, and an
    /// invisible window reports `canBecomeMain == false`, so the lookup below would no longer find it.
    private weak var lockedWindow: NSWindow?
    /// Main window frame before lock-in; restored by exitLocked.
    private var savedFrame: NSRect?
    private var panel: MiniTimerPanel?
    private var spirit: SpiritPanel?
    /// True when the circle is standing in for the mini timer, so opening chat centers the window.
    private var spiritReplacesTimer = false

    init(model: AppModel) {
        self.model = model
    }

    /// appFrame non-nil: put main window there and show LockedView. nil: hide main window, show mini timer.
    func enterLocked(appFrame: CGRect?) {
        let window = Self.visibleMainWindow() ?? lockedWindow
        lockedWindow = window
        if savedFrame == nil {
            savedFrame = window?.frame
        }
        if let appFrame {
            closePanel()
            closeSpirit()
            guard let window else { return }
            window.setFrame(appFrame, display: true, animate: true)
            bringToFront(window)
            reapplyFrameAfterSwiftUIUpdate(appFrame, to: window)
        } else {
            window?.orderOut(nil)
            closePanel()
            showSpirit(replacesTimer: true)
        }
    }

    /// Brings the locked-in main window (the chat screen) to the front. Does nothing unless a session is locked in,
    /// so a late assistant message or a wake-up can never pop the window up afterwards.
    /// Mini timer click (and the assistant needing the user while only the mini timer shows): the window is
    /// centered at 900x600. When the window already sits in its app zone (no mini timer), it only comes forward.
    func showMainWindow() {
        guard model.engine.isLocked else { return }
        guard let window = lockedWindow ?? Self.visibleMainWindow() else {
            NSApp.activate()
            return
        }
        if (panel != nil || spiritReplacesTimer), let visible = ScreenGeometry.mainVisibleFrame() {
            window.setFrame(LockedLayout.centeredFrame(size: LockedLayout.windowSize, in: visible), display: true)
        }
        bringToFront(window)
        window.orderFrontRegardless()
    }

    /// Mini timer ✕: shows the main window, then asks LockedView to start the end flow
    /// (give-up sheet before a goal is reached, otherwise the "End this session?" confirmation).
    func requestEnd() {
        showMainWindow()
        NotificationCenter.default.post(name: .tofuRequestEnd, object: nil)
    }

    /// Close mini timer, restore main window frame, bring app to front.
    func exitLocked() {
        closePanel()
        closeSpirit()
        let window = lockedWindow ?? Self.visibleMainWindow()
        let frame = savedFrame
        savedFrame = nil
        lockedWindow = nil
        guard let window else {
            NSApp.activate()
            return
        }
        if let frame {
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
        bringToFront(window)
    }

    // MARK: Helpers

    /// The SwiftUI main window: a visible, non-panel, non-sheet window that can become main.
    private static func visibleMainWindow() -> NSWindow? {
        NSApp.windows.first(where: { !($0 is NSPanel) && $0.sheetParent == nil && $0.canBecomeMain })
    }

    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showPanel() {
        closePanel()
        let panel = MiniTimerPanel(engine: model.engine,
                                   onOpen: { [weak self] in self?.showMainWindow() },
                                   onEnd: { [weak self] in self?.requestEnd() })
        panel.show()
        self.panel = panel
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// The circle that replaces the mini timer, or appears only long enough to say something.
    private func showSpirit(replacesTimer: Bool) {
        closeSpirit()
        spiritReplacesTimer = replacesTimer
        let spirit = SpiritPanel(engine: model.engine,
                                 onOpen: { [weak self] in self?.showMainWindow() },
                                 onEnd: { [weak self] in self?.requestEnd() })
        spirit.hidesWhenQuiet = !replacesTimer
        if replacesTimer { spirit.showDrifting() }
        self.spirit = spirit
    }

    private func closeSpirit() {
        spirit?.hideSpirit()
        spirit = nil
        spiritReplacesTimer = false
    }

    /// Flies to the browser window, grows, and says what happened. Arc cannot report a tab's pixels,
    /// so the circle stops on the top edge of the browser window.
    func note(_ notice: SpiritNotice) {
        guard model.engine.isLocked else { return }
        if spirit == nil { showSpirit(replacesTimer: false) }
        let window = model.engine.subject.map { WindowPlacer.largestOnScreenFrame(bundleID: $0.browser.bundleID) } ?? nil
        switch notice {
        case .tabClosed(let host):
            spirit?.approach(quartzWindow: window, text: SpiritLines.closedTab(host), mood: .roll, linger: 3.5)
        case .appHidden(let name):
            spirit?.approach(quartzWindow: window, text: SpiritLines.appHidden(name), mood: .bounce, linger: 3.5)
        case .question(let host, let title):
            spirit?.approach(quartzWindow: window, text: SpiritLines.question(host: host, title: title),
                             mood: .bounce, linger: nil)
        }
    }

    /// RootView swaps to LockedView on SwiftUI's next update. Until then the previous content's minimum
    /// size can clamp the new frame, so apply it once more shortly after, if the session is still locked.
    private func reapplyFrameAfterSwiftUIUpdate(_ frame: CGRect, to window: NSWindow) {
        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, let window, self.model.engine.isLocked, window.frame != frame else { return }
            window.setFrame(frame, display: true)
        }
    }
}
