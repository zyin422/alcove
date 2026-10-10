import AppKit

// PLACEHOLDER: Task 14 replaces this whole file with the real window handling and mini timer.

/// Live implementation of WindowPresenting. For now it does nothing: the main window stays where it is
/// and RootView swaps to LockedView while a session runs.
@MainActor final class MainWindowPresenter: WindowPresenting {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func enterLocked(appFrame: CGRect?) {}

    func exitLocked() {}
}
