import SwiftUI

/// App entry point: a single main window ("New Window" is disabled), the Settings scene (⌘,) and, while locked in,
/// a menu-bar timer. The AppDelegate owns the model.
@main
struct TofuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("menuBarTimer") private var menuBarTimer = true

    var body: some Scene {
        WindowGroup("Tofu", id: "main") {
            if AppDelegate.isRunningTests {
                Text("Running tests")
            } else {
                RootView(model: appDelegate.model)
            }
        }
        // The sidebar's tinted chrome runs up behind the traffic lights, as in Arc.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                if !AppDelegate.isRunningTests {
                    CheckForUpdatesButton(updates: appDelegate.model.updates)
                }
            }
        }

        MenuBarExtra(isInserted: Binding(
            get: { menuBarTimer && !AppDelegate.isRunningTests && appDelegate.model.engine.isLocked },
            set: { menuBarTimer = $0 })) {
            if !AppDelegate.isRunningTests {
                MenuBarTimerMenu(model: appDelegate.model, presenter: { appDelegate.windowPresenter })
            }
        } label: {
            if AppDelegate.isRunningTests {
                Text("Tofu")
            } else {
                MenuBarTimerLabel(engine: appDelegate.model.engine)
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

/// The menu bar's clock while locked in: break time left, goal time left, or time so far.
private struct MenuBarTimerLabel: View {
    let engine: SessionEngine

    var body: some View {
        let seconds = engine.breakRemaining ?? engine.remaining ?? engine.elapsed
        Text((engine.isOnBreak ? "☕ " : "🔒 ") + TimeFormat.clock(seconds))
            .monospacedDigit()
    }
}

/// The menu-bar timer's menu.
private struct MenuBarTimerMenu: View {
    let model: AppModel
    let presenter: () -> MainWindowPresenter?

    var body: some View {
        if let session = model.engine.session {
            Text(model.engine.isOnBreak ? "On a break from \(session.subjectName)" : "Locked in on \(session.subjectName)")
        }
        Divider()
        Button("Show Tofu") { presenter()?.showMainWindow() }
        Button("End Session…") { presenter()?.requestEnd() }
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
