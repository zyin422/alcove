import SwiftUI

/// App entry point: a single main window ("New Window" is disabled) plus the Settings scene (⌘,).
/// The AppDelegate owns the model.
@main
struct AlcoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Alcove", id: "main") {
            if AppDelegate.isRunningTests {
                Text("Running tests")
            } else {
                RootView(model: appDelegate.model)
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                if !AppDelegate.isRunningTests {
                    CheckForUpdatesButton(updates: appDelegate.model.updates)
                }
            }
        }

        Settings {
            if AppDelegate.isRunningTests {
                Text("Running tests")
            } else {
                SettingsView(model: appDelegate.model)
                    .frame(width: 560, height: 640)
            }
        }
    }
}

/// "Check for Updates…" in the app menu; disabled unless this is a release build (made by scripts/release.sh), where Sparkle isn't running.
private struct CheckForUpdatesButton: View {
    let updates: UpdateCenter

    var body: some View {
        Button("Check for Updates…") { updates.checkNow() }
            .disabled(!updates.canCheckForUpdates)
    }
}
