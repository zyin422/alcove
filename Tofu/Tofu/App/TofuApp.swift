import SwiftUI

/// Pure formatting rules for the macOS Menu Bar live status item (unit-tested).
enum MenuBarStatusSummary {
    static func label(
        isLocked: Bool,
        subjectName: String?,
        gracePassRemaining: TimeInterval? = nil,
        breakRemaining: TimeInterval?,
        sessionRemaining: TimeInterval?,
        sessionElapsed: TimeInterval,
        forceCountdownRemaining: TimeInterval?,
        todayFocusedSeconds: TimeInterval
    ) -> (title: String, systemImage: String) {
        if isLocked {
            if let gracePassRemaining, gracePassRemaining > 0 {
                return ("Pass \(TimeFormat.clock(gracePassRemaining))", "shield.lefthalf.filled")
            }
            if let breakRemaining {
                return ("Break \(TimeFormat.clock(max(0, breakRemaining)))", "cup.and.saucer.fill")
            }
            let name = subjectName ?? "Focus"
            let clockSeconds = sessionRemaining ?? sessionElapsed
            return ("\(name) · \(TimeFormat.clock(max(0, clockSeconds)))", "lock.shield.fill")
        }
        if let forceCountdownRemaining, forceCountdownRemaining > 0 {
            return ("Next block \(TimeFormat.clock(forceCountdownRemaining))", "timer")
        }
        if todayFocusedSeconds > 0 {
            return ("Tofu · \(TimeFormat.short(todayFocusedSeconds))", "shield.fill")
        }
        return ("Tofu", "shield")
    }
}

/// App entry point: a single main window ("New Window" is disabled), MenuBarExtra status HUD, and Settings scene (⌘,).
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
            CommandGroup(after: .appInfo) {
                if !AppDelegate.isRunningTests {
                    CheckForUpdatesButton(updates: appDelegate.model.updates)
                }
            }
            if !AppDelegate.isRunningTests {
                CommandMenu("Navigate") {
                    Button("Plan") {
                        appDelegate.model.selection = .today
                    }
                    .keyboardShortcut("1", modifiers: .command)
                    .disabled(appDelegate.model.engine.isLocked)

                    Button("Stats") {
                        appDelegate.model.selection = .stats
                    }
                    .keyboardShortcut("2", modifiers: .command)
                    .disabled(appDelegate.model.engine.isLocked)
                }
            }
        }

        MenuBarExtra {
            if !AppDelegate.isRunningTests {
                TofuMenuBarContent(model: appDelegate.model)
            }
        } label: {
            if AppDelegate.isRunningTests {
                Label("Tofu", systemImage: "shield")
            } else {
                TofuMenuBarLabel(model: appDelegate.model)
            }
        }
        .menuBarExtraStyle(.menu)

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

private struct TofuMenuBarLabel: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: model.engine.isLocked || model.nextForceBlockDeadline != nil ? 1 : 30)) { context in
            let todayKey = DayKey.key(for: context.date)
            let focusedToday = model.data.sessions
                .filter { $0.outcome == .completed && !$0.isDemo && DayKey.key(for: $0.start) == todayKey }
                .reduce(0.0) { $0 + $1.duration }
            let forceRemaining = (!model.engine.isLocked && !model.isStudyCompleted(day: todayKey))
                ? model.nextForceBlockDeadline.map { max(0, $0.timeIntervalSince(context.date)) }
                : nil
            let status = MenuBarStatusSummary.label(
                isLocked: model.engine.isLocked,
                subjectName: model.engine.subject?.name,
                gracePassRemaining: model.engine.gracePassRemaining,
                breakRemaining: model.engine.breakRemaining,
                sessionRemaining: model.engine.remaining,
                sessionElapsed: model.engine.elapsed,
                forceCountdownRemaining: forceRemaining,
                todayFocusedSeconds: focusedToday
            )
            Label(status.title, systemImage: status.systemImage)
                .monospacedDigit()
        }
    }
}

private struct TofuMenuBarContent: View {
    let model: AppModel

    var body: some View {
        let dayKey = DayKey.key(for: max(model.engine.now, Date()))
        let focusedToday = model.data.sessions
            .filter { $0.outcome == .completed && !$0.isDemo && DayKey.key(for: $0.start) == dayKey }
            .reduce(0.0) { $0 + $1.duration }
        let targetSeconds = TimeInterval(max(1, model.data.settings.dailyTargetMinutes) * 60)
        let pct = min(100, Int(((focusedToday / targetSeconds) * 100).rounded()))
        let openPriorities = model.todayPlan().priorities.filter { !$0.isDone }

        Text("Today: \(TimeFormat.short(focusedToday)) / \(TimeFormat.short(targetSeconds)) (\(pct)%)")
        if let top = openPriorities.first {
            Text("Up next: \(top.title)")
        }

        if !openPriorities.isEmpty {
            Menu("Mark Priority Done (\(openPriorities.count))") {
                ForEach(openPriorities.prefix(8)) { priority in
                    let subName = priority.subjectID.flatMap(model.subject(id:))?.name
                    let starPrefix = priority.isAnchor ? "★ " : ""
                    let metaParts = [subName, priority.estimatedMinutes.map { "\($0)m" }].compactMap { $0 }
                    let label = metaParts.isEmpty
                        ? "\(starPrefix)\(priority.title)"
                        : "\(starPrefix)\(priority.title) (\(metaParts.joined(separator: " · ")))"
                    Button(label) {
                        model.setPriority(priority.id, done: true, day: dayKey)
                        ToastCenter.shared.show("Completed “\(priority.title)” ✓")
                    }
                }
            }
        }

        Divider()

        Button("Open Tofu Window") {
            model.onShowMainWindow?()
        }

        Button("Park Thought…") {
            model.onToggleQuickThought?()
        }

        Divider()

        if model.engine.isLocked {
            if model.engine.isOnGracePass {
                Button("End 2m Grace Pass") {
                    model.engine.endGracePass()
                }
            }
            if model.engine.isOnBreak {
                Button("Resume Focus Block") {
                    model.engine.endBreak()
                }
            } else if model.engine.canTakeBreak {
                Button("Take 5m Break") {
                    _ = model.engine.beginBreak(minutes: 5)
                }
            }
            if model.engine.session?.mode.goalSeconds != nil {
                Button("Extend Block +10m") {
                    model.engine.extendSession(minutes: 10)
                    ToastCenter.shared.show("Extended block by +10m")
                }
            }
        } else {
            if let next = openPriorities.first(where: { $0.subjectID != nil }),
               let subjectID = next.subjectID,
               let subject = model.subject(id: subjectID) {
                Button("Lock in “\(next.title)” (\(subject.name))") {
                    let minutes = next.estimatedMinutes ?? 50
                    model.selectActivePriority(next.id, for: subject.id, day: dayKey, notify: false)
                    Task {
                        await model.lockIn(subjectID: subject.id, mode: .goal(minutes: minutes))
                    }
                }
            }
            if !model.data.subjects.isEmpty {
                Menu("Quick Lock In") {
                    let assigned = openPriorities.filter { $0.subjectID != nil }.prefix(5)
                    if !assigned.isEmpty {
                        Section("Open Priorities") {
                            ForEach(assigned) { priority in
                                if let sid = priority.subjectID, let sub = model.subject(id: sid) {
                                    let est = priority.estimatedMinutes ?? 50
                                    Button("\(priority.title) (\(sub.name) · \(est)m)") {
                                        model.selectActivePriority(priority.id, for: sub.id, day: dayKey, notify: false)
                                        Task { await model.lockIn(subjectID: sub.id, mode: .goal(minutes: est)) }
                                    }
                                }
                            }
                        }
                    }
                    Section("Subjects (50m)") {
                        ForEach(model.data.subjects) { sub in
                            Button(sub.name) {
                                Task { await model.lockIn(subjectID: sub.id, mode: .goal(minutes: 50)) }
                            }
                        }
                    }
                }
            }
            Button("15m Planning Mode") {
                Task { await model.startPlanningMode() }
            }
        }

        Divider()

        Menu("Music: \(model.data.settings.focusMusicMode.rawValue)") {
            ForEach(FocusMusicMode.allCases) { mode in
                Button {
                    model.updateSettings {
                        $0.focusMusicMode = mode
                        if mode == .off { $0.focusSound = .off }
                    }
                    model.syncBackgroundMusic()
                } label: {
                    if model.data.settings.focusMusicMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
            if FocusAudioEngine.shared.isPlaying && FocusAudioEngine.shared.activePlaylist != nil {
                Divider()
                Button("Next Track") {
                    _ = FocusAudioEngine.shared.nextTrack()
                }
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
