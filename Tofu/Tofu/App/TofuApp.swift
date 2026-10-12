import SwiftUI

/// App entry point: a single main window ("New Window" is disabled) plus the Settings scene (⌘,).
/// The AppDelegate owns the model.
@main
struct TofuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Tofu", id: "main") {
            if AppDelegate.isRunningTests {
                Text("Running tests")
            } else {
                RootView(model: appDelegate.model)
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
