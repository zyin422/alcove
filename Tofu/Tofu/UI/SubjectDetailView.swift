import SwiftUI

/// Pure metrics calculation for a subject's historical telemetry.
struct SubjectTelemetry: Equatable {
    var totalSeconds: TimeInterval
    var thisWeekSeconds: TimeInterval
    var completedCount: Int
    var averageDurationSeconds: TimeInterval
    var longestDurationSeconds: TimeInterval
    var totalDeflections: Int
    var activePrioritiesCount: Int
    var sevenDayMinutes: [Double]
    var sevenDayLabels: [String]

    var totalTimeLabel: String {
        let hours = Int(totalSeconds) / 3600
        let mins = (Int(totalSeconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    var thisWeekLabel: String {
        TimeFormat.short(thisWeekSeconds)
    }

    var avgDurationLabel: String {
        let mins = Int(averageDurationSeconds) / 60
        return mins > 0 ? "\(mins)m" : "<1m"
    }

    var longestDurationLabel: String {
        let hours = Int(longestDurationSeconds) / 3600
        let mins = (Int(longestDurationSeconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    static func calculate(subjectID: UUID, sessions: [Session], dayPlans: [DayPlan], now: Date = Date()) -> SubjectTelemetry {
        let matching = sessions.filter { $0.subjectID == subjectID && $0.outcome == .completed && !$0.isDemo }
        let total = matching.reduce(0.0) { $0 + $1.duration }
        let engine = StatsEngine(now: now)
        let thisWeek = engine.seconds(for: subjectID, in: matching, window: .week)
        let activity = engine.subjectRecentActivity(subjectID: subjectID, sessions: matching, days: 7)
        let count = matching.count
        let avg = count > 0 ? total / Double(count) : 0
        let longest = matching.map(\.duration).max() ?? 0
        let deflections = matching.reduce(0) { $0 + $1.blockedAttempts + $1.closedTabs }
        let currentDay = DayPlanner.workingDay(now: now, plans: dayPlans)
        let todayPlan = dayPlans.first { $0.day == currentDay }
        let active = todayPlan?.priorities.filter { $0.subjectID == subjectID && !$0.isDone }.count ?? 0

        return SubjectTelemetry(
            totalSeconds: total,
            thisWeekSeconds: thisWeek,
            completedCount: count,
            averageDurationSeconds: avg,
            longestDurationSeconds: longest,
            totalDeflections: deflections,
            activePrioritiesCount: active,
            sevenDayMinutes: activity.map(\.minutes),
            sevenDayLabels: activity.map(\.label)
        )
    }

    static func recentSessions(subjectID: UUID, sessions: [Session], limit: Int = 3) -> [Session] {
        Array(
            sessions
                .filter { $0.subjectID == subjectID && $0.outcome == .completed && !$0.isDemo }
                .sorted { $0.start > $1.start }
                .prefix(limit)
        )
    }
}

/// One subject's page: its name, the LOCK IN button, and the whole setup edited in place.
/// There is no separate edit sheet; valid changes save as they are made.
struct SubjectDetailView: View {
    let model: AppModel
    let subject: Subject
    @State private var form: SubjectFormState
    /// What this view last wrote to the model. A `subject` that differs arrived from somewhere
    /// else (e.g. a session saving an allowed site) and replaces the draft.
    @State private var lastSaved: Subject
    @State private var isChoosingMode = false
    @State private var targetPriorityForLockIn: Priority?
    @State private var quickPriorityDraft = ""
    @State private var isTestingWorkspace = false

    init(model: AppModel, subject: Subject) {
        self.model = model
        self.subject = subject
        _form = State(initialValue: SubjectFormState(subject: subject))
        _lastSaved = State(initialValue: subject)
    }

    var body: some View {
        let telemetry = SubjectTelemetry.calculate(
            subjectID: subject.id,
            sessions: model.data.sessions,
            dayPlans: model.data.dayPlans
        )

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    TextField("Name", text: $form.name)
                        .textFieldStyle(.plain)
                        .font(Theme.titleFont)
                    Menu {
                        Button("Duplicate “\(subject.name)”") {
                            model.duplicateSubject(id: subject.id)
                        }
                        Button("Copy Setup Summary") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(LockInWorkspaceSummary.clipboardText(subject: subject), forType: .string)
                            ToastCenter.shared.show("Copied setup summary")
                        }
                        Divider()
                        Button("View in Stats") {
                            model.selection = .stats
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Subject actions")
                }
                HStack(spacing: Theme.Space.s) {
                    Button {
                        targetPriorityForLockIn = nil
                        isChoosingMode = true
                    } label: {
                        Text("LOCK IN")
                            .tracking(3)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)

                    Button {
                        let draft = form.errors.isEmpty
                            ? form.subject(id: subject.id, createdAt: subject.createdAt)
                            : subject
                        isTestingWorkspace = true
                        Task {
                            await model.previewWorkspace(for: draft)
                            isTestingWorkspace = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingWorkspace {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "macwindow.on.rectangle")
                            }
                            Text("Test Setup")
                        }
                        .frame(minHeight: 56)
                        .padding(.horizontal, Theme.Space.m)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isTestingWorkspace || model.engine.isLocked)
                    .help("Launch configured websites and app windows now without starting a Lock-In session")
                }
                
                telemetryBentoGrid(telemetry)

                subjectPrioritiesSection

                recentSessionsSection

                SubjectForm(form: $form, showsName: false)
                if !form.errors.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(form.errors, id: \.self) { message in
                            Text(message).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(subject.name)
        .onChange(of: form) { autosave() }
        .onChange(of: subject) { _, changed in
            guard changed != lastSaved else { return }
            form = SubjectFormState(subject: changed)
            lastSaved = changed
        }
        .sheet(isPresented: $isChoosingMode) {
            LockInSheet(model: model, subject: subject, initialPriority: targetPriorityForLockIn)
        }
    }

    private var subjectPrioritiesSection: some View {
        let todayKey = DayKey.key(for: Date())
        let tasks = model.todayPlan().priorities.filter { $0.subjectID == subject.id }
        let color = Theme.subjectColor(subject.colorHex)

        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .foregroundStyle(color)
                    Text("TODAY'S PRIORITIES FOR \(subject.name.uppercased())")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)
                }
                Spacer()
                let openCount = tasks.filter { !$0.isDone }.count
                Text(tasks.isEmpty ? "No tasks planned" : "\(openCount) open · \(tasks.count - openCount) done")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !tasks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(tasks) { priority in
                        HStack(spacing: Theme.Space.s) {
                            Button {
                                model.setPriority(priority.id, done: !priority.isDone, day: todayKey)
                            } label: {
                                Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(priority.isDone ? Theme.emerald : Color.secondary)
                            }
                            .buttonStyle(.plain)

                            Text(priority.title)
                                .strikethrough(priority.isDone)
                                .foregroundStyle(priority.isDone ? .secondary : .primary)
                                .lineLimit(1)

                            if priority.isAnchor {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.amber)
                            }
                            if let est = priority.estimatedMinutes {
                                Text("\(est)m")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !priority.isDone {
                                Menu {
                                    ForEach([15, 25, 45, 60, 90], id: \.self) { mins in
                                        Button("\(mins)m") {
                                            model.updatePriorityDetails(
                                                priority.id,
                                                day: todayKey,
                                                title: priority.title,
                                                subjectID: priority.subjectID,
                                                estimatedMinutes: mins
                                            )
                                        }
                                    }
                                    if priority.estimatedMinutes != nil {
                                        Divider()
                                        Button("Clear") {
                                            model.updatePriorityDetails(
                                                priority.id,
                                                day: todayKey,
                                                title: priority.title,
                                                subjectID: priority.subjectID,
                                                estimatedMinutes: nil
                                            )
                                        }
                                    }
                                } label: {
                                    Text(priority.estimatedMinutes.map { "\($0)m" } ?? "+ Est")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Adjust estimated minutes")

                                Button {
                                    model.togglePriorityAnchor(priority.id, day: todayKey)
                                } label: {
                                    Image(systemName: priority.isAnchor ? "star.fill" : "star")
                                        .font(.system(size: 11))
                                        .foregroundStyle(priority.isAnchor ? Theme.amber : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Toggle focus anchor")

                                Button("Lock in") {
                                    targetPriorityForLockIn = priority
                                    isChoosingMode = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 7)
                        if priority.id != tasks.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }

            HStack(spacing: Theme.Space.s) {
                TextField("Add priority for \(subject.name) (e.g. Finish problem set 45m)", text: $quickPriorityDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSubjectPriority)
                Button("Add", action: addSubjectPriority)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(quickPriorityDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: Theme.Space.xs) {
                ForEach([25, 45, 60], id: \.self) { mins in
                    Button("+\(mins)m") {
                        let base = quickPriorityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        quickPriorityDraft = base.isEmpty ? "\(mins)m " : "\(base) \(mins)m"
                    }
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        )
    }

    private func addSubjectPriority() {
        let raw = quickPriorityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        var priority = ThoughtParkingEngine.promoteThoughtToPriority(thought: raw, subjects: model.data.subjects)
        priority.subjectID = subject.id
        let todayKey = DayKey.key(for: Date())
        model.updatePlan(day: todayKey) { $0.priorities.append(priority) }
        quickPriorityDraft = ""
    }

    @ViewBuilder private var recentSessionsSection: some View {
        let recent = SubjectTelemetry.recentSessions(subjectID: subject.id, sessions: model.data.sessions)
        if !recent.isEmpty {
            let color = Theme.subjectColor(subject.colorHex)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundStyle(color)
                        Text("RECENT SESSIONS & REFLECTION NOTES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                    }
                    Spacer()
                    Button("View in Stats →") {
                        model.selection = .stats
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                VStack(spacing: 6) {
                    ForEach(recent) { session in
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Text(session.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 118, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Theme.Space.s) {
                                    Text(TimeFormat.short(session.duration))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                    let deflect = session.blockedAttempts + session.closedTabs
                                    Text(deflect == 0 ? "Clean focus" : "\(deflect) deflected")
                                        .font(.caption2)
                                        .foregroundStyle(deflect == 0 ? Theme.emerald : Theme.amber)
                                }
                                if let note = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                        Text("“\(note)”")
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Spacer(minLength: 4)
                                        Button("+ Plan") {
                                            if let created = SessionSummaryText.followUpPriority(
                                                from: note,
                                                fallbackSubjectID: subject.id,
                                                subjects: model.data.subjects
                                            ) {
                                                let todayKey = DayKey.key(for: Date())
                                                model.updatePlan(day: todayKey) { $0.priorities.append(created) }
                                                ToastCenter.shared.show("Added “\(created.title)” to today")
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .help("Turn this note into a priority for today")
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                    }
                }
            }
            .padding(Theme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.02))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
            )
        }
    }

    /// Saves the form whenever it is valid; an invalid draft keeps the last valid state saved.
    private func autosave() {
        guard form.errors.isEmpty else { return }
        let updated = form.subject(id: subject.id, createdAt: subject.createdAt)
        guard updated != lastSaved else { return }
        lastSaved = updated
        model.updateSubject(updated)
    }

    private func telemetryBentoGrid(_ telemetry: SubjectTelemetry) -> some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                // Hero card (Total Focus)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text("TOTAL FOCUS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.subjectColor(subject.colorHex))
                        Spacer()
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.subjectColor(subject.colorHex).opacity(0.8))
                    }
                    Text(telemetry.totalTimeLabel)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("\(telemetry.completedCount) completed session\(telemetry.completedCount == 1 ? "" : "s") · \(telemetry.thisWeekLabel) this week")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let peakMin = telemetry.sevenDayMinutes.max(), peakMin > 0 {
                        let subjColor = Theme.subjectColor(subject.colorHex)
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(telemetry.sevenDayMinutes.enumerated()), id: \.offset) { idx, mins in
                                let frac = max(0.12, min(1.0, mins / peakMin))
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(mins > 0 ? subjColor : Color.primary.opacity(0.10))
                                        .frame(width: 14, height: mins > 0 ? max(4, 18 * CGFloat(frac)) : 3)
                                    Text(idx < telemetry.sevenDayLabels.count ? telemetry.sevenDayLabels[idx] : "")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.tertiary)
                                }
                                .help("\(Int(mins.rounded()))m")
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.subjectColor(subject.colorHex).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.subjectColor(subject.colorHex).opacity(0.2), lineWidth: 1)
                        )
                )

                // Companion card 1: Average Session
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text("AVG SESSION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(telemetry.avgDurationLabel)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Deep work cadence")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                )
            }

            HStack(spacing: Theme.Space.s) {
                // Companion card 2: Longest Block
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("LONGEST BLOCK")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "trophy")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(telemetry.longestDurationLabel)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                )

                // Companion card 3: Distraction Shield Deflections
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("SHIELD DEFLECTIONS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 11))
                            .foregroundStyle(telemetry.totalDeflections > 0 ? Theme.amber : .secondary)
                    }
                    Text("\(telemetry.totalDeflections) intercepted")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(telemetry.totalDeflections > 0 ? Theme.amber : .primary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                )

                // Companion card 4: Active Priorities
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("TASKS REMAINING")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "checklist")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.indigo)
                    }
                    Text("\(telemetry.activePrioritiesCount) today")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.indigo)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                )
            }
        }
    }
}
