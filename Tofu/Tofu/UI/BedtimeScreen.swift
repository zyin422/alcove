import AppKit
import SwiftUI

/// Window policy for full-screen Bedtime guard (unit-tested).
enum BedtimeWindowPolicy {
    static func frames(covering screens: [CGRect]) -> [CGRect] {
        screens.filter { $0.width >= 1 && $0.height >= 1 }
    }
}

/// Full-screen window that intercepts key events and refuses closing until dismissed.
private final class BedtimeWindow: NSWindow {
    var allowsClose = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func close() {
        if allowsClose { super.close() }
    }
}

/// Manages full-screen lock windows across all active screens when past midnight.
@MainActor final class BedtimeWindowController {
    private let model: AppModel
    private var windows: [BedtimeWindow] = []
    private var coveredFrames: [CGRect] = []
    private var observers: [NSObjectProtocol] = []
    private var guardTimer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if windows.isEmpty { createWindows() }
        startGuarding()
        reassert()
    }

    func hide() {
        stopGuarding()
        tearDownWindows()
    }

    private func createWindows() {
        let frames = BedtimeWindowPolicy.frames(covering: NSScreen.screens.map(\.frame))
        guard !frames.isEmpty else { return }
        let hostIndex = frames.firstIndex(of: NSScreen.main?.frame ?? .null) ?? 0
        coveredFrames = frames
        for (index, frame) in frames.enumerated() {
            let window = BedtimeWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.allowsClose = false
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.backgroundColor = .windowBackgroundColor
            window.setFrame(frame, display: true)
            if index == hostIndex {
                window.contentView = NSHostingView(rootView: BedtimeView(model: model))
            }
            windows.append(window)
        }
    }

    private func reassert() {
        guard !windows.isEmpty else { return }
        let alreadyUp = windows.allSatisfy(\.isVisible) && NSApp.isActive
        guard !alreadyUp else { return }
        for window in windows {
            window.orderFrontRegardless()
        }
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        windows.first { $0.contentView is NSHostingView<BedtimeView> }?.makeKey()
    }

    private func refit() {
        let frames = BedtimeWindowPolicy.frames(covering: NSScreen.screens.map(\.frame))
        guard frames != coveredFrames else { return }
        let wasUp = !windows.isEmpty
        tearDownWindows()
        guard wasUp else { return }
        createWindows()
        reassert()
    }

    private func startGuarding() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification,
            NSApplication.didChangeScreenParametersNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if note.name == NSApplication.didChangeScreenParametersNotification {
                        self?.refit()
                    }
                    self?.reassert()
                }
            })
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassert() }
        }
        RunLoop.main.add(timer, forMode: .common)
        guardTimer = timer
    }

    private func stopGuarding() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        guardTimer?.invalidate()
        guardTimer = nil
    }

    private func tearDownWindows() {
        for window in windows {
            window.allowsClose = true
            window.orderOut(nil)
        }
        windows.removeAll()
        coveredFrames = []
    }
}

/// Full-screen bedtime prompt shown past midnight to prevent unconstrained late-night usage.
struct BedtimeView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()

            VStack(spacing: Theme.Space.m) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Past Midnight")
                    .font(.system(size: 40, weight: .semibold))

                Text("The day is finished. Computer access is locked for rest.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Space.m) {
                let canPlan = model.canPlanTonight()
                Button {
                    Task { await model.startPlanningFromBedtime() }
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "timer")
                        Text("15m Planning Mode")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 320)
                .disabled(!canPlan)
                .opacity(canPlan ? 1.0 : 0.4)

                if canPlan {
                    Text("Set tomorrow's priorities, read your AI feed, check messages (5m Discord limit).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 320)
                } else {
                    Text("Planning mode was already used tonight. Rest now to recharge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 320)
                }

                Button {
                    sleepDisplay()
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "bed.double.fill")
                        Text("Go to Sleep")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 320)

                HStack(spacing: Theme.Space.l) {
                    if model.canPostponeMorning {
                        Button("Not now (10 min)") {
                            model.postponeMorning()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)

                        Button("Open Plan") {
                            model.openPlan()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("10-minute delay used today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, Theme.Space.xs)
            }
            .padding(.top, Theme.Space.m)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            VoiceOutput.shared.speak("It is past midnight. The day is complete. Time to sleep and protect your energy.")
        }
    }

    private func sleepDisplay() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }
}
