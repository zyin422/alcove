import SwiftUI

/// App entry point: a single main window ("New Window" is disabled). The AppDelegate owns the model.
@main
struct AccountabilibrosisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Accountabilibrosis", id: "main") {
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
    }
}
