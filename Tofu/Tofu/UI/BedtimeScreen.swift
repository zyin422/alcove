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
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.backgroundColor = NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1.0)
            window.setFrame(frame, display: true)
            if index == hostIndex {
                window.contentView = NSHostingView(rootView: BedtimeView(model: model))
            }
            windows.append(window)
        }
    }

    private func reassert() {
        guard !windows.isEmpty else { return }
        let alreadyUp = windows.allSatisfy { $0.isVisible && $0.isOnActiveSpace }
            && NSApp.isActive
            && windows.contains(where: \.isKeyWindow)
        guard !alreadyUp else { return }
        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            window.orderFrontRegardless()
        }
        windows.first { $0.contentView is NSHostingView<BedtimeView> }?.makeKeyAndOrderFront(nil)
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
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = DayPlanner.bedtimeSecondsRemaining(now: context.date)
            let canPlan = model.canPlanTonight(now: context.date)

            VStack(spacing: Theme.Space.xl) {
                Spacer()

                VStack(spacing: Theme.Space.l) {
                    // Nocturnal lock header pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.amber)
                            .frame(width: 7, height: 7)
                        Text("NOCTURNAL LOCKDOWN • 00:00 – 04:00")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.amber)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Theme.amber.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Theme.amber.opacity(0.3), lineWidth: 1)
                    )

                    VStack(spacing: Theme.Space.m) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.amber)
                            .shadow(color: Theme.amber.opacity(0.4), radius: 16)

                        Text("Past Midnight")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("The day is finished. Computer access is locked for rest.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)

                        if remaining > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.caption.weight(.semibold))
                                Text("Lock active for \(TimeFormat.short(remaining)) • Lifts at 4:00 AM")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 2)
                        }
                    }
                }

                VStack(spacing: Theme.Space.m) {
                    Button {
                        Task { await model.startPlanningFromBedtime() }
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: "timer")
                            Text("15m Planning Mode")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NocturnalPrimaryButtonStyle())
                    .frame(width: 320)
                    .disabled(!canPlan)
                    .opacity(canPlan ? 1.0 : 0.4)

                    if canPlan {
                        Text("Set tomorrow's priorities, read your AI feed, check messages (5m Discord limit).")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .frame(width: 320)
                    } else {
                        Text("Planning mode was already used tonight. Rest now to recharge.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
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
                    .buttonStyle(NocturnalSecondaryButtonStyle())
                    .frame(width: 320)

                    HStack(spacing: Theme.Space.l) {
                        if model.canPostponeMorning {
                            Button("Delay Lock (10 min)") {
                                model.postponeMorning()
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.white.opacity(0.7))

                            Button("Open Plan") {
                                model.openPlan()
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("10-minute delay used today")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.top, Theme.Space.xs)
                }
                .padding(.top, Theme.Space.m)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.11),
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            FocusAudioEngine.shared.stop()
            VoiceOutput.shared.speak("It is past midnight. The day is complete. Time to sleep and protect your energy.")
        }
    }

    private func sleepDisplay() {
        FocusAudioEngine.shared.stop()
        VoiceOutput.shared.unloadKokoro()
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }
}
