import AppKit

/// Asks the user whether a site is needed when the relevance check could not decide (no key, offline, refusal).
/// The question is an alert, a sheet on the key window when there is a plain one, else a modal alert.
@MainActor final class NeedPrompt: NeedPrompting {
    func askIfNeeded(host: String, subject: String) async -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Is \(host) needed for \(subject)?"
        alert.informativeText = "Couldn't check this page automatically."
        alert.addButton(withTitle: "Needed")        // first button: the default
        alert.addButton(withTitle: "Close tab")

        let response: NSApplication.ModalResponse
        // Panels (mini timer, toasts) are too small to carry a sheet, and a window that already shows a sheet
        // would make this one wait; both fall back to a modal alert.
        if let window = NSApp.keyWindow, window.isVisible, !(window is NSPanel), window.attachedSheet == nil {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        return response == .alertFirstButtonReturn
    }
}
