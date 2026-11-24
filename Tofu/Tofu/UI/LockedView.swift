import AppKit
import SwiftUI

extension Color {
    /// Pure white in light mode and pure black in dark mode: the background of the lock-in screens.
    static let lockBackground = Color(nsColor: NSColor(name: "lockBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    })
}

/// Pure layout and text rules for the locked main window (unit-tested).
enum LockedLayout {
    /// Size of the main window when it is brought up from the mini timer.
    static let windowSize = CGSize(width: 900, height: 600)

    /// Window width below which the session info stacks on top of the chat instead of sitting beside it.
    static let stackedBelowWidth: CGFloat = 640
    /// Width of the session info pane beside the chat.
    static let sidePaneWidth: CGFloat = 280
    /// Smallest the chat column may get beside the info pane.
    static let chatMinWidth: CGFloat = 360
    /// Largest timer size in the info pane.
    static let sideTimerMaxFontSize: CGFloat = 44

    /// True when a window of `width` is too narrow for chat and info side by side.
    static func isStacked(width: CGFloat) -> Bool {
        width < stackedBelowWidth
    }

    /// Timer size for an info pane `paneWidth` wide (content width): 44 pt, smaller when the pane is narrow.
    static func sideTimerFontSize(paneWidth: CGFloat) -> CGFloat {
        min(sideTimerMaxFontSize, timerFontSize(for: CGSize(width: paneWidth, height: 200)))
    }

    /// Timer font size for the space it gets: min(width / 5, height * 0.42), never below 1 pt.
    static func timerFontSize(for size: CGSize) -> CGFloat {
        let fitted = min(size.width / 5.0, size.height * 0.42)
        guard fitted.isFinite else { return 1 }
        return max(1, fitted)
    }

    /// Goal progress from 0 to 1. A goal of zero or less counts as reached.
    static func progress(elapsed: TimeInterval, goal: TimeInterval) -> Double {
        guard goal > 0 else { return 1 }
        return min(1, max(0, elapsed / goal))
    }

    /// "3 apps blocked · 2 tabs closed", singular for 1.
    static func countersText(blocked: Int, tabs: Int) -> String {
        let apps = blocked == 1 ? "app" : "apps"
        let tabWord = tabs == 1 ? "tab" : "tabs"
        return "\(blocked) \(apps) blocked · \(tabs) \(tabWord) closed"
    }

    /// "goal 50m", "goal 1h 30m".
    static func goalCaption(goalSeconds: TimeInterval) -> String {
        "goal \(TimeFormat.short(goalSeconds))"
    }

    /// `size` centered in `visible`, shrunk to fit when the screen is smaller. Origin rounded down to whole points.
    static func centeredFrame(size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = visible.minX + ((visible.width - width) / 2).rounded(.down)
        let y = visible.minY + ((visible.height - height) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Chat screen shown in the main window while locked: the conversation with the study buddy on the left, a
/// compact session pane (subject, timer, goal progress, counters, End) on the right. Below 640 pt of width the
/// pane stacks on top of the chat. It re-renders every tick because it reads `engine.now` (through
/// `elapsed`/`remaining`). The mini timer's ✕ starts the same end flow as the End button.
struct LockedView: View {
    let model: AppModel
    @State private var isShowingMirror = false
    @State private var sessionTab: SessionTab = .assistant

    private enum SessionTab: String, CaseIterable {
        case assistant = "Assistant"
        case plan = "Plan"
        case thoughts = "Parked Thoughts"
        case closedTabs = "Closed Tabs"
    }

    var body: some View {
        GeometryReader { proxy in
            let stacked = LockedLayout.isStacked(width: proxy.size.width)
            // AnyLayout keeps the chat's identity (typed text, open microphone) when the window crosses the breakpoint.
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                if stacked {
                    stackedInfo(engine: model.engine, width: proxy.size.width)
                    separator(stacked: true)
                }
                mainContent(stacked: stacked)
                if !stacked {
                    separator(stacked: false)
                    sideInfo(engine: model.engine)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lockBackground)
        .sheet(isPresented: $isShowingMirror) {
            MirrorSheet(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tofuRequestEnd)) { _ in
            endTapped()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tofuShowThoughts)) { _ in
            sessionTab = .thoughts
        }
    }

    @ViewBuilder
    private func mainContent(stacked: Bool) -> some View {
        if model.engine.isOnBreak {
            BreakGuideView(engine: model.engine)
                .frame(minWidth: stacked ? nil : LockedLayout.chatMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $sessionTab) {
                    ForEach(SessionTab.allCases, id: \.self) { tab in
                        Text(tabTitle(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Theme.Space.m)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xs)

                // Hidden shortcut buttons for ⌘1...⌘4
                HStack(spacing: 0) {
                    Button("") { sessionTab = .assistant }.keyboardShortcut("1", modifiers: .command)
                    Button("") { sessionTab = .plan }.keyboardShortcut("2", modifiers: .command)
                    Button("") { sessionTab = .thoughts }.keyboardShortcut("3", modifiers: .command)
                    Button("") { sessionTab = .closedTabs }.keyboardShortcut("4", modifiers: .command)
                }
                .frame(width: 0, height: 0)
                .opacity(0)

                if sessionTab == .plan {
                    PlanningPriorityView(model: model)
                } else if sessionTab == .thoughts {
                    ParkedThoughtsView(engine: model.engine)
                } else if sessionTab == .closedTabs {
                    ClosedTabsRecoveryView(engine: model.engine)
                } else {
                    ChatView(assistant: model.assistant)
                }
            }
            .frame(minWidth: stacked ? nil : LockedLayout.chatMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if model.engine.isPlanningMode {
                    sessionTab = .plan
                }
            }
        }
    }

    private func tabTitle(_ tab: SessionTab) -> String {
        switch tab {
        case .assistant:
            return "Assistant (⌘1)"
        case .plan:
            return "Plan (⌘2)"
        case .thoughts:
            let count = model.engine.parkedThoughts.count
            return count > 0 ? "Thoughts (\(count)) ⌘3" : "Thoughts (⌘3)"
        case .closedTabs:
            let count = model.engine.deflectionsCount
            return count > 0 ? "Shield (\(count)) ⌘4" : "Shield (⌘4)"
        }
    }

    // MARK: Session info

    /// Right pane beside the chat: subject, timer, goal progress, counters and End, top to bottom.
    private func sideInfo(engine: SessionEngine) -> some View {
        let contentWidth = LockedLayout.sidePaneWidth - 2 * Theme.Space.l
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            subjectCaption(engine: engine)
            timerText(engine: engine, width: contentWidth)
            if engine.isPlanningMode {
                planningBadge()
            }
            breakLine(engine: engine)
            gracePassLine(engine: engine)
            goalBlock(engine: engine, barWidth: nil)
            focusSoundControl
            countersText(engine: engine)
            Spacer(minLength: Theme.Space.m)
            endButton
        }
        .padding(Theme.Space.l)
        .frame(width: LockedLayout.sidePaneWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Narrow window: the same information as a compact band above the chat.
    private func stackedInfo(engine: SessionEngine, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                subjectCaption(engine: engine)
                timerText(engine: engine, width: max(0, width / 2 - Theme.Space.m))
                if engine.isPlanningMode {
                    planningBadge()
                }
                breakLine(engine: engine)
                gracePassLine(engine: engine)
                goalBlock(engine: engine, barWidth: 160)
            }
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.s) {
                countersText(engine: engine)
                endButton
            }
        }
        .padding(Theme.Space.m)
    }

    private func separator(stacked: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
    }

    private func subjectCaption(engine: SessionEngine) -> some View {
        let name = engine.session?.subjectName ?? ""
        let color = Theme.subjectColor(SubjectColor.hex(for: name))
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name)
                .font(Theme.captionFont)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func timerText(engine: SessionEngine, width: CGFloat) -> some View {
        Text(TimeFormat.clockFull(engine.remaining ?? engine.elapsed))
            .font(Theme.timerFont(size: LockedLayout.sideTimerFontSize(paneWidth: width)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// Goal progress line and "goal 50m" caption, only in goal mode. `barWidth` nil = as wide as the pane.
    @ViewBuilder private func goalBlock(engine: SessionEngine, barWidth: CGFloat?) -> some View {
        if let goal = engine.session?.mode.goalSeconds {
            let color: Color = {
                if let name = engine.session?.subjectName {
                    return Theme.subjectColor(SubjectColor.hex(for: name))
                }
                return Theme.indigo
            }()
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: barWidth, height: 3)
                    .frame(maxWidth: barWidth == nil ? .infinity : nil)
                    .overlay(alignment: .leading) {
                        GeometryReader { bar in
                            Rectangle()
                                .fill(color)
                                .frame(width: bar.size.width * LockedLayout.progress(elapsed: engine.elapsed, goal: goal))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(LockedLayout.goalCaption(goalSeconds: goal))
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Button("+5m") { engine.extendSession(minutes: 5) }
                        Button("+10m") { engine.extendSession(minutes: 10) }
                        Button("+15m") { engine.extendSession(minutes: 15) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private func countersText(engine: SessionEngine) -> some View {
        let blocked = engine.session?.blockedAttempts ?? 0
        let tabs = engine.session?.closedTabs ?? 0
        return Group {
            if blocked > 0 || tabs > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.rose)
                    Text(LockedLayout.countersText(blocked: blocked, tabs: tabs))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.rose)
                }
            } else {
                Text(LockedLayout.countersText(blocked: 0, tabs: 0))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var endButton: some View {
        Button("End") { endTapped() }
            .buttonStyle(SecondaryButtonStyle())
    }

    @ViewBuilder private func breakLine(engine: SessionEngine) -> some View {
        if let remaining = engine.breakRemaining {
            HStack(spacing: 5) {
                Circle().fill(Theme.coral).frame(width: 6, height: 6)
                Text("Break \(TimeFormat.clockFull(remaining))")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.coral)
                    .monospacedDigit()
            }
            Button("End break") { engine.endBreak() }
                .buttonStyle(SecondaryButtonStyle())
        } else if engine.canTakeBreak {
            Button("Take a break") { _ = engine.beginBreak(minutes: MirrorTurn.breakDefault) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder private func gracePassLine(engine: SessionEngine) -> some View {
        if engine.isOnGracePass, let remaining = engine.gracePassRemaining {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Theme.amber)
                    .font(.system(size: 11, weight: .bold))
                Text("Pass \(TimeFormat.clockFull(remaining))")
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(Theme.amber)
                    .monospacedDigit()
                Button("End") { engine.endGracePass() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.amber.opacity(0.12)))
        }
    }

    /// End always opens the Mirror. The session stops only if they confirm a stop there.
    /// Shared by the End button and the mini timer's ✕.
    private func endTapped() {
        isShowingMirror = true
    }

    private func planningBadge() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 11))
            Text("Planning Mode: Arc & Tools")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.indigo.opacity(0.12))
        )
        .foregroundStyle(Theme.indigo)
    }

    private var focusSoundControl: some View {
        Menu {
            Section("Soundscape") {
                ForEach(FocusSound.allCases) { sound in
                    Button {
                        model.updateSettings { $0.focusSound = sound }
                        FocusAudioEngine.shared.play(sound)
                    } label: {
                        if FocusAudioEngine.shared.activeSound == sound {
                            Label(sound.rawValue, systemImage: "checkmark")
                        } else {
                            Text(sound.rawValue)
                        }
                    }
                }
            }
            if FocusAudioEngine.shared.isPlaying {
                Section("Volume") {
                    Button("Mute") {
                        model.updateSettings { $0.focusSound = .off }
                        FocusAudioEngine.shared.stop()
                    }
                    Button("25% Volume") {
                        model.updateSettings { $0.focusSoundVolume = 0.25 }
                        FocusAudioEngine.shared.volume = 0.25
                    }
                    Button("50% Volume") {
                        model.updateSettings { $0.focusSoundVolume = 0.50 }
                        FocusAudioEngine.shared.volume = 0.50
                    }
                    Button("75% Volume") {
                        model.updateSettings { $0.focusSoundVolume = 0.75 }
                        FocusAudioEngine.shared.volume = 0.75
                    }
                    Button("100% Volume") {
                        model.updateSettings { $0.focusSoundVolume = 1.00 }
                        FocusAudioEngine.shared.volume = 1.00
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: FocusAudioEngine.shared.isPlaying ? "waveform" : "waveform.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(FocusAudioEngine.shared.isPlaying ? Theme.indigo : Color.secondary)
                Text(FocusAudioEngine.shared.activeSound == .off ? "Sound: Off" : FocusAudioEngine.shared.activeSound.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FocusAudioEngine.shared.isPlaying ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(FocusAudioEngine.shared.isPlaying ? Theme.indigo.opacity(0.12) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(FocusAudioEngine.shared.isPlaying ? Theme.indigo.opacity(0.3) : Color.clear, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Ambient focus sound")
    }
}

/// Direct in-session priority editor during 15-minute planning mode.
private struct PlanningPriorityView: View {
    let model: AppModel
    @State private var newTitle = ""
    @State private var newSubjectID: UUID?

    private var plan: DayPlan { model.todayPlan() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("DAY PRIORITIES")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                Text("Check off tasks or add priorities for today while your 15m timer runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)

            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(plan.priorities) { priority in
                        priorityRow(priority)
                    }
                    if plan.priorities.isEmpty {
                        Text("No priorities set yet. Add one below.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Theme.Space.xl)
                    }
                }
                .padding(.horizontal, Theme.Space.m)
            }

            HStack(spacing: Theme.Space.s) {
                TextField("Add a priority", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                SetupPicker(subjects: model.data.subjects, selection: $newSubjectID)
                    .frame(width: 140)
                Button("Add", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.Space.m)
            .background(Color.primary.opacity(0.04))
        }
    }

    private func priorityRow(_ priority: Priority) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                model.setPriority(priority.id, done: !priority.isDone, day: plan.day)
            } label: {
                Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(priority.title)
                    .strikethrough(priority.isDone)
                    .foregroundStyle(priority.isDone ? .secondary : .primary)
                if let subject = priority.subjectID.flatMap(model.subject(id:)) {
                    Text(subject.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.updatePlan(day: plan.day) { $0.priorities.removeAll { $0.id == priority.id } }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let subjectID = newSubjectID ?? DayPlanner.matchSubject(title, subjects: model.data.subjects)
        model.updatePlan(day: plan.day) { $0.priorities.append(Priority(title: title, subjectID: subjectID)) }
        newTitle = ""
        newSubjectID = nil
    }
}

/// In-session scratchpad to park intrusive ideas or urgent reminders without leaving lock-in.
private struct ParkedThoughtsView: View {
    let engine: SessionEngine
    @State private var newThoughtText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(engine.parkedThoughts.isEmpty ? "Parked Thoughts" : "Parked Thoughts (\(engine.parkedThoughts.count))")
                        .font(.headline)
                    Text("Jot down intrusive ideas or tasks here to preserve your focus. You can review them when the session ends.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !engine.parkedThoughts.isEmpty {
                    Button {
                        let subName = engine.session?.subjectName ?? "Focus"
                        let dateStr = DayKey.key(for: Date())
                        let md = ThoughtParkingEngine.exportMarkdown(thoughts: engine.parkedThoughts, subjectName: subName, dateString: dateStr)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Markdown")
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.02))

            Divider()

            if engine.parkedThoughts.isEmpty {
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No parked thoughts yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Type any random thought below and press Enter to save it for later.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(engine.parkedThoughts.enumerated()), id: \.offset) { index, thought in
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            Circle()
                                .fill(Color.primary.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            Text(thought)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(thought, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy to clipboard")
                            Button {
                                engine.removeParkedThought(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack(spacing: Theme.Space.xs) {
                tagButton("Idea", prefix: "[Idea] ")
                tagButton("Task", prefix: "[Task] ")
                tagButton("Reminder", prefix: "[Reminder] ")
                tagButton("Question", prefix: "[Question] ")
                Spacer()
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.xs)

            HStack(spacing: Theme.Space.s) {
                TextField("Park a thought for later… (Enter to save)", text: $newThoughtText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submit()
                    }
                Button("Save") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newThoughtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Theme.Space.m)
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    private func tagButton(_ title: String, prefix: String) -> some View {
        Button {
            if !newThoughtText.hasPrefix(prefix) {
                newThoughtText = prefix + newThoughtText
            }
            isFieldFocused = true
        } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.indigo.opacity(0.12)))
                .foregroundStyle(Theme.indigo)
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let trimmed = newThoughtText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        engine.addParkedThought(trimmed)
        newThoughtText = ""
    }
}

/// Drawer showing all interventions (blocked apps and closed browser tabs) during the session.
private struct ClosedTabsRecoveryView: View {
    let engine: SessionEngine

    private var closed: [String] { engine.session?.closedTabHistory ?? [] }
    private var blocked: [String] { engine.session?.blockedAppHistory ?? [] }
    private var totalCount: Int { closed.count + blocked.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text("SHIELD & DEFLECTIONS (\(totalCount))")
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !closed.isEmpty {
                        Button("Copy URLs") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(closed.joined(separator: "\n"), forType: .string)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .controlSize(.small)
                    }
                }
                Text("Distractions deflected while you locked in. Nothing was permanently lost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)

            if totalCount == 0 {
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.indigo)
                    Text("Clean focus. Zero distractions deflected so far.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        if !blocked.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text("BLOCKED APPS (\(blocked.count))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.rose)
                                ForEach(Array(blocked.enumerated()), id: \.offset) { index, app in
                                    HStack(spacing: Theme.Space.s) {
                                        Image(systemName: "lock.slash.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.rose)
                                        Text(app)
                                            .font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Text("Blocked")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Theme.rose.opacity(0.12)))
                                            .foregroundStyle(Theme.rose)
                                    }
                                    .padding(.horizontal, Theme.Space.m)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                                }
                            }
                        }

                        if !closed.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text("OFF-TASK TABS (\(closed.count))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.amber)
                                ForEach(Array(closed.enumerated()), id: \.offset) { index, host in
                                    HStack(spacing: Theme.Space.s) {
                                        Image(systemName: "safari")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                        Text(host)
                                            .font(.system(size: 13, design: .monospaced))
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(host, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy URL")

                                        Text("#\(index + 1)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, Theme.Space.m)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.m)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
