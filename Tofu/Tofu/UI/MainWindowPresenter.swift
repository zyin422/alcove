import AppKit

/// One AppKit window, reduced to what the single-window rule needs.
struct MainWindowCandidate: Equatable {
    var id: String
    var isPanel: Bool
    var isBorderless: Bool
    var canBecomeMain: Bool
    var isSheet: Bool
    var title: String

    /// The SwiftUI document window. Panels, sheets, and the borderless morning screen are not it.
    var isDocument: Bool { !isPanel && !isSheet && !isBorderless && canBecomeMain }
}

/// Tofu has one document window. A lock-in must not leave a second one beside it.
enum MainWindowPolicy {
    /// Document windows to close. `keeping` stays; a separate Settings window stays too.
    /// With no known window, the first document window stays and the later ones close.
    static func windowsToClose(_ windows: [MainWindowCandidate], keeping: String?) -> [String] {
        let documents = windows.filter(\.isDocument)
        guard let keep = keeping ?? documents.first?.id else { return [] }
        return documents.filter { $0.id != keep && $0.title != "Settings" }.map(\.id)
    }
}

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
    /// Bumped when the block ends so a late sweep does not close a window the user opened afterwards.
    private var sweepGeneration = 0

    init(model: AppModel) {
        self.model = model
        model.onStudyCompleted = { [weak self] in
            self?.closeBetweenBlocksPanel()
        }
    }

    /// appFrame non-nil: put main window there and show LockedView. nil: hide main window, show mini timer.
    func enterLocked(appFrame: CGRect?) {
        let window = Self.visibleMainWindow() ?? lockedWindow
        lockedWindow = window
        if let window { reveal(window) }
        if savedFrame == nil {
            savedFrame = window?.frame
        }
        if let appFrame {
            closePanel()
            guard let window else { return }
            window.setFrame(appFrame, display: true, animate: true)
            bringToFront(window)
            reapplyFrameAfterSwiftUIUpdate(appFrame, to: window)
        } else {
            if let window { hideWithoutClosing(window) }
            showPanel()
        }
        sweepExtrasSoon()
    }

    /// The dock click brings the window we already have instead of letting SwiftUI open another.
    func showExistingWindow() {
        guard let window = lockedWindow ?? Self.visibleMainWindow() else { return }
        if model.engine.isLocked {
            showMainWindow()
            return
        }
        reveal(window)
        bringToFront(window)
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
        if panel != nil, let visible = ScreenGeometry.mainVisibleFrame() {
            window.setFrame(LockedLayout.centeredFrame(size: LockedLayout.windowSize, in: visible), display: true)
        }
        reveal(window)
        bringToFront(window)
        window.orderFrontRegardless()
        closeExtras()
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
        let window = lockedWindow ?? Self.visibleMainWindow()
        let frame = savedFrame
        savedFrame = nil
        lockedWindow = nil
        sweepGeneration += 1
        if let window {
            reveal(window)
            if let frame {
                window.setFrame(frame, display: true, animate: window.isVisible)
            }
            bringToFront(window)
        } else {
            NSApp.activate()
        }
        if model.secondsUntilNextForceBlock != nil && !model.isStudyCompleted() {
            showBetweenBlocksPanel()
        }
    }

    // MARK: Helpers

    /// The SwiftUI main window: not a panel, sheet, or the borderless morning screen.
    static func visibleMainWindow() -> NSWindow? {
        NSApp.windows.first(where: isDocumentWindow)
    }

    static func isDocumentWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.sheetParent == nil && !window.styleMask.contains(.borderless) && window.canBecomeMain
    }

    /// Parks the window offscreen without ordering it out, so SwiftUI still counts it as open.
    private func hideWithoutClosing(_ window: NSWindow) {
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.setFrameOrigin(NSPoint(x: -window.frame.width - 2000, y: -window.frame.height - 2000))
    }

    private func reveal(_ window: NSWindow) {
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.isExcludedFromWindowsMenu = false
    }

    private func sweepExtrasSoon() {
        sweepGeneration += 1
        let generation = sweepGeneration
        closeExtras()
        for delay in [0.3, 1.0] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.sweepGeneration == generation, self.model.engine.isLocked else { return }
                self.closeExtras()
            }
        }
    }

    /// Closes a Tofu window that appeared after the block started. Panels opened for the block stay.
    private func closeExtras() {
        let candidates = NSApp.windows.map { window in
            MainWindowCandidate(id: Self.identity(window),
                                isPanel: window is NSPanel,
                                isBorderless: window.styleMask.contains(.borderless),
                                canBecomeMain: window.canBecomeMain,
                                isSheet: window.sheetParent != nil,
                                title: window.title)
        }
        let closing = Set(MainWindowPolicy.windowsToClose(candidates, keeping: lockedWindow.map(Self.identity)))
        for window in NSApp.windows where closing.contains(Self.identity(window)) {
            window.close()
        }
    }

    private static func identity(_ window: NSWindow) -> String {
        String(UInt(bitPattern: ObjectIdentifier(window)))
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
        let panel = MiniTimerPanel(engine: model.engine, model: model,
                                   onOpen: { [weak self] in self?.showMainWindow() },
                                   onEnd: { [weak self] in self?.requestEnd() },
                                   onParkThought: { [weak self] in
                                       guard let self else { return }
                                       QuickThoughtPanelController.shared.toggle(
                                           engine: self.model.engine,
                                           model: self.model,
                                           onParked: { [weak self] thought in
                                               self?.showThoughtNotice(thought)
                                           },
                                           onPromoted: { [weak self] thought in
                                               self?.showThoughtNotice("Priority: \(thought) 🎯")
                                           }
                                       )
                                   },
                                   onCycleSound: { [weak self] in
                                       guard let self else { return }
                                       let current = self.model.data.settings.focusSound
                                       let next = FocusAudioEngine.nextSound(after: current)
                                       self.model.updateSettings { $0.focusSound = next }
                                       FocusAudioEngine.shared.play(next)
                                       let notice = next == .off ? "Sound: Off 🔇" : "Sound: \(next.rawValue) 🎧"
                                       self.panel?.showNotice(notice)
                                   },
                                   onToggleMute: { [weak self] in
                                       guard let self else { return }
                                       let current = self.model.data.settings.focusSound
                                       let toggled = FocusAudioEngine.toggleMute(current: current)
                                       self.model.updateSettings { $0.focusSound = toggled }
                                       FocusAudioEngine.shared.play(toggled)
                                       let notice = toggled == .off ? "Sound: Muted 🔇" : "Sound: \(toggled.rawValue) 🎧"
                                       self.panel?.showNotice(notice)
                                   })
        panel.show()
        self.panel = panel
    }

    private func showBetweenBlocksPanel() {
        closePanel()
        let panel = MiniTimerPanel(engine: model.engine, model: model,
                                   onOpen: { [weak self] in self?.showExistingWindow() },
                                   onEnd: { [weak self] in self?.closePanel() },
                                   onLockIn: { [weak self] in
                                       self?.showExistingWindow()
                                       self?.model.startMyDay()
                                   })
        panel.show()
        self.panel = panel
    }

    func closeBetweenBlocksPanel() {
        closePanel()
    }

    /// Syncs the between-blocks mini-timer panel: shows when a force-block countdown is running and study is not done.
    func syncBetweenBlocksPanel() {
        guard !model.engine.isLocked else { return }
        if model.secondsUntilNextForceBlock != nil && !model.isStudyCompleted() {
            if panel == nil {
                showBetweenBlocksPanel()
            }
        } else {
            closeBetweenBlocksPanel()
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Flashes confirmation of a parked stray thought on the active HUD or toast banner.
    func showThoughtNotice(_ thought: String) {
        if let panel {
            panel.showNotice("Parked: “\(thought)”")
        } else {
            ToastCenter.shared.show("Parked thought: “\(thought)”")
        }
    }

    /// Intervention notices (e.g. off-task tab closed or app hidden) are shown in the mini timer tab.
    func note(_ notice: SpiritNotice) {
        guard model.engine.isLocked else { return }
        let message: String
        switch notice {
        case .tabClosed(let host):
            message = SpiritLines.closedTab(host)
        case .appHidden(let name):
            message = SpiritLines.appHidden(name)
        case .question(let host, let title):
            message = SpiritLines.question(host: host, title: title)
        }
        panel?.showNotice(message)
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
