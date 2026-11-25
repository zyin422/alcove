import AppKit
import SwiftUI

/// The pick-priority screen stays up until a block starts. Closing the window or switching apps does not dismiss it.
enum MorningWindowPolicy {
    /// One full-screen frame per display. An empty display is left out.
    static func frames(covering screens: [CGRect]) -> [CGRect] {
        screens.filter { $0.width >= 1 && $0.height >= 1 }
    }

    /// True when strict priority mode blocks locking in until today has >= 1 open priority.
    static func requiresPriorityBeforeLockIn(settings: AppSettings, openPrioritiesCount: Int) -> Bool {
        settings.requirePriorityToLockIn && openPrioritiesCount == 0
    }
}

/// Borderless windows can't become key by default, and the morning screen has text fields and buttons.
/// Closing is refused until the controller hides the screen itself.
private final class MorningWindow: NSWindow {
    var allowsClose = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func close() {
        if allowsClose { super.close() }
    }
}

/// The full-screen "Good morning" window over every display. Shown and hidden through AppModel
/// (`onShowMorning` / `onHideMorning`). While it is up, switching apps or closing the window brings it back.
@MainActor final class MorningWindowController {
    private let model: AppModel
    private var windows: [MorningWindow] = []
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
        let frames = MorningWindowPolicy.frames(covering: NSScreen.screens.map(\.frame))
        guard !frames.isEmpty else { return }
        let hostIndex = frames.firstIndex(of: NSScreen.main?.frame ?? .null) ?? 0
        coveredFrames = frames
        for (index, frame) in frames.enumerated() {
            let window = MorningWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.allowsClose = false
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.backgroundColor = .windowBackgroundColor
            window.setFrame(frame, display: true)
            if index == hostIndex {
                window.contentView = NSHostingView(rootView: MorningView(model: model))
            }
            windows.append(window)
        }
    }

    /// Switching away, hiding the app, or closing the window brings the screen back.
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
        windows.first { $0.contentView is NSHostingView<MorningView> }?.makeKeyAndOrderFront(nil)
    }

    private func refit() {
        let frames = MorningWindowPolicy.frames(covering: NSScreen.screens.map(\.frame))
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

/// Greeting, today's unfinished priorities or other setups as cards, and LOCK IN on the chosen one.
struct MorningView: View {
    let model: AppModel
    private enum Target: Hashable {
        case priority(UUID)
        case subject(UUID)
    }
    @State private var selection: Target?
    /// Setups chosen here for priorities that had none (or a different one).
    @State private var chosenSetups: [UUID: UUID] = [:]
    @State private var option: LockInOption = .minutes50
    @State private var customMinutes = 45
    @State private var newTitle = ""

    private var plan: DayPlan { model.todayPlan() }
    private var open: [Priority] { plan.priorities.filter { !$0.isDone } }
    private var otherSubjects: [Subject] {
        let prioritizedIDs = Set(open.compactMap { setupID(for: $0) })
        return model.data.subjects.filter { !prioritizedIDs.contains($0.id) }
    }
    private var activeTarget: Target? {
        if let selection {
            switch selection {
            case .priority(let id):
                if open.contains(where: { $0.id == id }) { return selection }
            case .subject(let id):
                if model.subject(id: id) != nil { return selection }
            }
        }
        if let first = open.first { return .priority(first.id) }
        if let firstSubject = otherSubjects.first ?? model.data.subjects.first {
            return .subject(firstSubject.id)
        }
        return nil
    }
    private var selectedPriority: Priority? {
        guard case .priority(let id) = activeTarget else { return nil }
        return open.first { $0.id == id }
    }
    private var selectedSubject: Subject? {
        guard case .subject(let id) = activeTarget else { return nil }
        return model.subject(id: id)
    }

    private func setupID(for priority: Priority) -> UUID? {
        let id = chosenSetups[priority.id] ?? priority.subjectID
        return id.flatMap(model.subject(id:)) == nil ? nil : id
    }

    private var needsPriorityFirst: Bool {
        MorningWindowPolicy.requiresPriorityBeforeLockIn(
            settings: model.data.settings,
            openPrioritiesCount: open.count
        )
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            VStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.m) {
                    BotAvatar(size: 64)
                    Button {
                        VoiceOutput.shared.speak("\(DayPlanner.greeting(at: Date())), \(firstName). What are you starting with today?")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Repeat spoken greeting")
                }
                Text("\(DayPlanner.greeting(at: Date())), \(firstName)")
                    .font(.system(size: 48, weight: .semibold))
                Text((DayKey.date(for: plan.day) ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                let streak = StatsEngine(now: Date()).summary(model.data.sessions).currentStreak
                let targetHours = model.data.settings.dailyTargetMinutes / 60
                HStack(spacing: 6) {
                    if streak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.amber)
                        Text("\(streak)-day streak ·")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Daily goal: \(targetHours)h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            if model.data.settings.googleShowEventsEnabled,
               let events = model.googleSync?.todayEvents, !events.isEmpty {
                eventsBlock(events)
            }

            if (open.isEmpty && otherSubjects.isEmpty) || needsPriorityFirst {
                emptyState
            } else {
                Text("What are you starting with?").font(.title2)
                cardsList
                startControls
                if open.isEmpty {
                    addPriorityRow
                }
            }
            Spacer()
            HStack(spacing: Theme.Space.l) {
                if model.isStudyCompleted() {
                    Button("Done for the day") {
                        model.dismissMorning()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                } else if model.canPostponeMorning {
                    Button("Not now (10 min)") {
                        model.postponeMorning()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                    Button("Open Plan") {
                        model.openPlan()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    Text("10-minute delay used today")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if model.canPlanToday {
                    Button("15m Planning Mode") {
                        Task { await model.startPlanningMode() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    Text("15m Planning used today")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, Theme.Space.xl)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncSuggestedDuration()
            let greeting = "\(DayPlanner.greeting(at: Date())), \(firstName). What are you starting with today?"
            VoiceOutput.shared.speak(greeting)
        }
        .onChange(of: activeTarget) { _, _ in
            syncSuggestedDuration()
        }
    }

    private func syncSuggestedDuration() {
        if let est = selectedPriority?.estimatedMinutes,
           let suggestion = LockInOption.suggestedOption(for: est) {
            option = suggestion.option
            customMinutes = suggestion.customMinutes
        }
    }

    private var firstName: String {
        model.displayName.split(separator: " ").first.map(String.init) ?? model.displayName
    }

    /// Read-only list of the first few of today's Google Calendar events.
    private func eventsBlock(_ events: [GoogleEvent]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text("Today's events").font(.headline)
                if let alert = DayPlanner.nextCalendarAlert(in: events, at: Date()) {
                    let urgent = !alert.isOngoing && alert.minutes <= 30
                    let tint: Color = alert.isOngoing ? Theme.cyan : (urgent ? Theme.amber : Theme.indigo)
                    Text(alert.isOngoing ? "Now · \(alert.minutes)m left" : "\(alert.title) in \(alert.minutes)m")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.14)))
                        .foregroundStyle(tint)
                }
            }
            ForEach(events.prefix(5)) { event in
                HStack(spacing: Theme.Space.s) {
                    Text(GoogleEventFormat.timeLabel(event))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    Text(event.summary ?? "(untitled)")
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var cardsList: some View {
        let totalCount = open.count + otherSubjects.count
        return Group {
            if totalCount > 4 {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: Theme.Space.s) {
                        cardsContent
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: 560)
                .frame(maxHeight: 280)
            } else {
                VStack(spacing: Theme.Space.s) {
                    cardsContent
                }
                .frame(maxWidth: 560)
            }
        }
    }

    @ViewBuilder private var cardsContent: some View {
        ForEach(open) { card($0) }
        if !open.isEmpty && !otherSubjects.isEmpty {
            Text("Other subjects")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Space.xs)
        }
        ForEach(otherSubjects) { subjectCard($0) }
    }

    private func card(_ priority: Priority) -> some View {
        let isSelected = activeTarget == .priority(priority.id)
        let subject = (setupID(for: priority) ?? priority.subjectID).flatMap(model.subject(id:))
        let color = subject.map { Theme.subjectColor($0.colorHex) } ?? Theme.indigo
        return Button {
            selection = .priority(priority.id)
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? color : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(priority.title).font(.title3.weight(.medium))
                    HStack(spacing: 6) {
                        if let subject {
                            HStack(spacing: 4) {
                                Circle().fill(color).frame(width: 5, height: 5)
                                Text(subject.name).font(.callout.weight(.medium)).foregroundStyle(color)
                            }
                        } else {
                            Text("No setup yet").font(.callout).foregroundStyle(.secondary)
                        }
                        if priority.isAnchor {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.system(size: 9))
                                Text("Anchor").font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.amber.opacity(0.16)))
                            .foregroundStyle(Theme.amber)
                        }
                        if let est = priority.estimatedMinutes {
                            Text("· \(est)m")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                HStack(spacing: Theme.Space.xs) {
                    Button {
                        model.togglePriorityAnchor(priority.id, day: plan.day)
                    } label: {
                        Image(systemName: priority.isAnchor ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundStyle(priority.isAnchor ? Theme.amber : .secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(priority.isAnchor ? "Remove focus anchor" : "Mark as focus anchor (★)")

                    if !model.data.settings.requirePriorityToLockIn || open.count > 1 {
                        Button {
                            model.setPriority(priority.id, done: true, day: plan.day)
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Mark “\(priority.title)” done")
                    }
                }
            }
            .padding(Theme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(isSelected ? color.opacity(0.08) : Color.clear)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(isSelected ? color : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func subjectCard(_ subject: Subject) -> some View {
        let isSelected = activeTarget == .subject(subject.id)
        let color = Theme.subjectColor(subject.colorHex)
        return Button {
            selection = .subject(subject.id)
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? color : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(subject.name).font(.title3.weight(.medium))
                    }
                    let details = subject.details.trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(details.isEmpty ? (open.isEmpty ? "Subject" : "Other subject") : details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(Theme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(isSelected ? color.opacity(0.08) : Color.clear)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(isSelected ? color : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isLockInDisabled: Bool {
        if let priority = selectedPriority {
            return setupID(for: priority) == nil
        }
        return selectedSubject == nil
    }

    private func performLockIn() {
        if let priority = selectedPriority {
            start(priority)
        } else if let subject = selectedSubject {
            startSubject(subject.id)
        }
    }

    @ViewBuilder private var startControls: some View {
        if selectedPriority != nil || selectedSubject != nil {
            VStack(spacing: Theme.Space.m) {
                if let priority = selectedPriority, setupID(for: priority) == nil {
                    HStack {
                        Text("Setup for “\(priority.title)”").foregroundStyle(.secondary)
                        SetupPicker(subjects: model.data.subjects, selection: Binding(
                            get: { chosenSetups[priority.id] },
                            set: { chosenSetups[priority.id] = $0 }))
                            .frame(width: 180)
                    }
                    if model.data.subjects.isEmpty {
                        Text("Create a setup in the main window first.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Picker("Length", selection: $option) {
                    ForEach(LockInOption.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 420)
                if option == .custom {
                    CustomMinutesField(minutes: $customMinutes)
                }
                if model.data.settings.googleShowEventsEnabled,
                   let events = model.googleSync?.todayEvents,
                   let alert = DayPlanner.nextCalendarAlert(in: events, at: Date()),
                   !alert.isOngoing, alert.minutes > 8, alert.minutes <= 90 {
                    let fitMins = LockInOption.clampedMinutes(alert.minutes - 5)
                    let currentGoalMins = option.mode(customMinutes: customMinutes).goalMinutes
                    let overlapsMeeting = currentGoalMins.map { $0 > alert.minutes } ?? true
                    Button {
                        option = .custom
                        customMinutes = fitMins
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: overlapsMeeting ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                                .font(.caption2)
                            Text("Fit before “\(alert.title)” (\(fitMins)m)")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill((overlapsMeeting ? Theme.amber : Theme.indigo).opacity(0.14)))
                        .foregroundStyle(overlapsMeeting ? Theme.amber : Theme.indigo)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    performLockIn()
                } label: {
                    Text("LOCK IN").tracking(3).frame(width: 240, height: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
                .disabled(isLockInDisabled)
                .opacity(isLockInDisabled ? 0.35 : 1)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Text("No priorities for today yet. What's first?").font(.title2)
            HStack {
                TextField("e.g. #cs128 Finish lab 45m", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(width: 420)
            quickPriorityTagRow
                .frame(width: 420)
        }
    }

    private var addPriorityRow: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack {
                TextField("e.g. #cs128 Finish lab 45m", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add priority", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            quickPriorityTagRow
        }
        .frame(width: 420)
        .padding(.top, Theme.Space.s)
    }

    @ViewBuilder private var quickPriorityTagRow: some View {
        if !model.data.subjects.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(model.data.subjects.prefix(5)) { sub in
                        let tag = "#" + sub.name.lowercased().replacingOccurrences(of: " ", with: "")
                        Button {
                            if !newTitle.localizedCaseInsensitiveContains(tag) {
                                newTitle = newTitle.isEmpty ? "\(tag) " : "\(newTitle) \(tag) "
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Theme.subjectColor(sub.colorHex))
                                    .frame(width: 5, height: 5)
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach([25, 45, 60], id: \.self) { mins in
                        Button {
                            newTitle = newTitle.isEmpty ? "\(mins)m " : "\(newTitle) \(mins)m"
                        } label: {
                            Text("+\(mins)m")
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var priority = ThoughtParkingEngine.promoteThoughtToPriority(thought: title, subjects: model.data.subjects)
        if priority.subjectID == nil {
            priority.subjectID = DayPlanner.matchSubject(priority.title, subjects: model.data.subjects)
        }
        model.updatePlan(day: plan.day) { $0.priorities.append(priority) }
        selection = .priority(priority.id)
        newTitle = ""
    }

    private func start(_ priority: Priority) {
        guard let subjectID = setupID(for: priority) else { return }
        model.selectActivePriority(priority.id, for: subjectID, day: plan.day, notify: false)
        let mode = option.mode(customMinutes: customMinutes)
        let model = model
        Task { await model.start(priority: priority, subjectID: subjectID, mode: mode) }
    }

    private func startSubject(_ subjectID: UUID) {
        let mode = option.mode(customMinutes: customMinutes)
        let model = model
        Task { await model.start(subjectID: subjectID, mode: mode) }
    }
}
