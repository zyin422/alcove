import SwiftUI

struct DailyGoalProgressSnapshot: Equatable {
    let dayTotalSeconds: TimeInterval
    let targetSeconds: TimeInterval
    let fraction: Double
    let percent: Int
    let isMet: Bool
}

/// Text and presentation rules for the end-of-session summary (unit-tested).
enum SessionSummaryText {
    /// Today's cumulative progress toward the user's daily target after completing a block.
    static func dailyGoalProgress(
        for session: Session,
        allSessions: [Session],
        dailyTargetMinutes: Int,
        calendar: Calendar = .current
    ) -> DailyGoalProgressSnapshot {
        let dayKey = DayKey.key(for: session.start, calendar: calendar)
        var includedCurrent = false
        var total: TimeInterval = 0
        for item in allSessions where item.outcome == .completed && !item.isDemo {
            if DayKey.key(for: item.start, calendar: calendar) == dayKey {
                total += item.duration
                if item.id == session.id { includedCurrent = true }
            }
        }
        if !includedCurrent && session.outcome == .completed && !session.isDemo {
            total += session.duration
        }
        let target = TimeInterval(max(1, dailyTargetMinutes) * 60)
        return DailyGoalProgressSnapshot(
            dayTotalSeconds: total,
            targetSeconds: target,
            fraction: min(1.0, total / target),
            percent: Int(((total / target) * 100).rounded()),
            isMet: total >= target
        )
    }

    /// Turns a non-empty post-session reflection note into a Today priority, defaulting to the block's subject.
    static func followUpPriority(
        from note: String,
        fallbackSubjectID: UUID,
        subjects: [Subject]
    ) -> Priority? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ThoughtParkingEngine.promoteThoughtToPriority(
            thought: trimmed,
            subjects: subjects,
            fallbackSubjectID: fallbackSubjectID
        )
    }
    /// "Completed" / "Bailed" / "Interrupted"; "Ended" when the session has no outcome yet.
    static func outcome(_ outcome: SessionOutcome?) -> String {
        switch outcome {
        case .completed: return "Completed"
        case .bailed: return "Bailed"
        case .interrupted: return "Interrupted"
        case nil: return "Ended"
        }
    }

    /// The goal duration ("50m", "1h 30m") in goal mode, nil in open mode.
    static func goal(_ mode: SessionMode) -> String? {
        mode.goalSeconds.map { TimeFormat.short($0) }
    }

    /// The summary follows a finished session; an interrupted one (the app quit) has no one to show it to.
    static func shouldPresent(_ session: Session?) -> Bool {
        guard let outcome = session?.outcome else { return false }
        return outcome != .interrupted
    }

    /// Clean focus purity percentage (0–100) for a single session after penalizing distraction events.
    static func focusPurityPercent(for session: Session) -> Int {
        guard session.duration > 0 else { return 100 }
        let penalty = Double(session.blockedAttempts + session.closedTabs) * 180.0
        let ratio = max(0.0, min(1.0, 1.0 - (penalty / session.duration)))
        return Int((ratio * 100.0).rounded())
    }

    /// Formats a single focus block into a clean Markdown recap.
    static func markdownRecap(session: Session, priority: Priority? = nil, notes: String? = nil) -> String {
        var lines: [String] = []
        let outcomeStr = outcome(session.outcome)
        lines.append("### 🎯 Focus Block: \(session.subjectName) (\(outcomeStr))")
        var meta = "- **Duration:** \(TimeFormat.short(session.duration))"
        if let g = goal(session.mode) {
            meta += " (Goal: \(g))"
        }
        lines.append(meta)
        if let priority {
            lines.append("- **Active Focus Priority:** \(priority.title) \(priority.isDone ? "✓" : "")")
        }
        lines.append("- **Shield Interventions:** \(session.blockedAttempts) apps blocked · \(session.closedTabs) tabs closed")
        let activeNotes = notes ?? session.notes
        if let activeNotes, !activeNotes.isEmpty {
            lines.append("- **Notes & Reflection:** \(activeNotes)")
        }
        if !session.parkedThoughts.isEmpty {
            lines.append("- **Parked Thoughts:**")
            for thought in session.parkedThoughts {
                lines.append("  - \(thought)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Sheet shown after a session ends (spec §6, end step 5): subject, outcome, time, counters and the goal.
struct SessionSummaryView: View {
    let model: AppModel
    let session: Session
    var onStartNext: ((Subject, Priority?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// The priority this lock-in worked on, asked about once ("Did you finish …?").
    @State private var priority: Priority?
    @State private var answered = false
    @State private var addedThoughtsToPlan = false
    @State private var notesText: String = ""
    @State private var addedNoteAsPriority = false
    @State private var copiedMarkdown = false
    @State private var copiedDiscord = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Session summary")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                        Text(session.subjectName)
                            .font(Theme.titleFont)
                            .lineLimit(2)
                        Text(SessionSummaryText.outcome(session.outcome))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

            VStack(spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    StatCard(title: "Duration", value: TimeFormat.short(session.duration), tint: Theme.indigo, icon: "clock.fill")
                    if let goal = SessionSummaryText.goal(session.mode) {
                        StatCard(title: "Goal", value: goal, tint: Theme.emerald, icon: "target")
                    } else {
                        let purity = SessionSummaryText.focusPurityPercent(for: session)
                        let purityTint: Color = purity >= 80 ? Theme.emerald : (purity >= 60 ? Theme.amber : Theme.coral)
                        StatCard(title: "Focus Purity", value: "\(purity)%", tint: purityTint, icon: "chart.line.uptrend.xyaxis")
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    StatCard(title: "Apps blocked", value: "\(session.blockedAttempts)", tint: session.blockedAttempts > 0 ? Theme.rose : nil, icon: "shield.fill")
                    StatCard(title: "Tabs closed", value: "\(session.closedTabs)", tint: session.closedTabs > 0 ? Theme.rose : nil, icon: "xmark.circle.fill")
                }
                dailyGoalProgressCard
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reflection & Notes")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                TextField("Add reflection or notes...", text: $notesText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: notesText) { _, val in
                        addedNoteAsPriority = false
                        model.updateSessionNotes(id: session.id, notes: val)
                    }
                if !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        if addedNoteAsPriority {
                            Label("Added to Today's Plan ✓", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.emerald)
                        } else {
                            Button {
                                if let created = SessionSummaryText.followUpPriority(
                                    from: notesText,
                                    fallbackSubjectID: session.subjectID,
                                    subjects: model.data.subjects
                                ) {
                                    let day = DayKey.key(for: Date())
                                    model.updatePlan(day: day) { $0.priorities.append(created) }
                                    addedNoteAsPriority = true
                                    ToastCenter.shared.show("Added follow-up priority: \(created.title)")
                                }
                            } label: {
                                Label("Add note as follow-up priority", systemImage: "plus.circle")
                                    .font(.caption2.weight(.medium))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.indigo)
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }

            HStack(spacing: Theme.Space.m) {
                Button {
                    copyMarkdownRecap()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedMarkdown ? "checkmark" : "doc.on.doc")
                        Text(copiedMarkdown ? "Copied Markdown ✓" : "Copy Markdown")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(copiedMarkdown ? Theme.emerald : Color.primary)
                }
                .buttonStyle(.borderless)

                Button {
                    copyDiscordRecap()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedDiscord ? "checkmark" : "bubble.left.and.bubble.right.fill")
                        Text(copiedDiscord ? "Copied Discord ✓" : "Copy Discord")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(copiedDiscord ? Theme.emerald : Color.primary)
                }
                .buttonStyle(.borderless)
            }

            if !session.parkedThoughts.isEmpty {
                parkedThoughtsSection
            }

            if !model.engine.relaunchOffer.isEmpty {
                relaunchList
            }

            if let priority {
                priorityCheck(priority)
            }

                    let next = DayPlanner.nextPriority(in: model.plan(for: DayKey.key(for: session.start)) ?? model.todayPlan(), excludingID: priority?.id)
                    if let next {
                        nextPrioritySection(next)
                    } else if let currentSubject = model.subject(id: session.subjectID), onStartNext != nil {
                        continueSubjectCard(currentSubject)
                    }
                }
            }
            .frame(maxHeight: 560)

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.l)
        .frame(width: 460)
        .onAppear {
            priority = model.priorityToConfirm(after: session)
            notesText = session.notes ?? ""
        }
        .onDisappear { model.engine.applyRelaunch() }
    }

    private var dailyGoalProgressCard: some View {
        let goal = SessionSummaryText.dailyGoalProgress(
            for: session,
            allSessions: model.data.sessions,
            dailyTargetMinutes: model.data.settings.dailyTargetMinutes
        )
        let accent: Color = goal.isMet ? Theme.emerald : Theme.indigo
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: goal.isMet ? "checkmark.seal.fill" : "flame.fill")
                        .font(.caption)
                        .foregroundStyle(accent)
                    Text("Today's Daily Goal")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Text(goal.isMet
                     ? "\(TimeFormat.short(goal.dayTotalSeconds)) · Met (\(goal.percent)%)"
                     : "\(TimeFormat.short(goal.dayTotalSeconds)) / \(TimeFormat.short(goal.targetSeconds)) (\(goal.percent)%)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * goal.fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.22), lineWidth: 1))
    }

    private var parkedThoughtsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Parked Thoughts (\(session.parkedThoughts.count))")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    let dateStr = DayKey.key(for: session.start)
                    let md = ThoughtParkingEngine.exportMarkdown(thoughts: session.parkedThoughts, subjectName: session.subjectName, dateString: dateStr)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.bordered)
            }
            ForEach(session.parkedThoughts.prefix(3), id: \.self) { thought in
                Text("• \(thought)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if session.parkedThoughts.count > 3 {
                Text("+ \(session.parkedThoughts.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !addedThoughtsToPlan {
                Button {
                    let todayKey = DayKey.key(for: Date())
                    let priorities = ThoughtParkingEngine.formatAsPriorities(
                        thoughts: session.parkedThoughts,
                        subjectID: session.subjectID,
                        subjects: model.data.subjects
                    )
                    model.updatePlan(day: todayKey) { plan in
                        plan.priorities.append(contentsOf: priorities)
                    }
                    addedThoughtsToPlan = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Add to Today's Plan")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            } else {
                Text("Added to Today's Plan ✓")
                    .font(.caption)
                    .foregroundStyle(Theme.emerald)
                    .padding(.top, 2)
            }
        }
        .padding(Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        )
    }

    private var relaunchList: some View {
        let allSelected = model.engine.relaunchOffer.allSatisfy(\.selected)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Bring back")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.engine.relaunchOffer.count > 1 {
                    Button(allSelected ? "Deselect all" : "Select all") {
                        let nextState = !allSelected
                        for choice in model.engine.relaunchOffer {
                            model.engine.setRelaunchSelection(choice.id, selected: nextState)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.indigo)
                }
            }
            Text("Checked tabs and apps open again when you close this.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(RelaunchChoice.Group.allCases, id: \.self) { group in
                        let rows = model.engine.relaunchOffer.filter { $0.group == group }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(group.rawValue)
                                    .font(Theme.captionFont)
                                    .foregroundStyle(.secondary)
                                ForEach(rows) { choice in
                                    Toggle(isOn: Binding(
                                        get: { model.engine.relaunchOffer.first { $0.id == choice.id }?.selected ?? false },
                                        set: { model.engine.setRelaunchSelection(choice.id, selected: $0) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(choice.title).lineLimit(1)
                                            Text(choice.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
        }
    }

    @ViewBuilder private func priorityCheck(_ priority: Priority) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if answered {
                let isAllDone = model.isStudyCompleted(day: DayKey.key(for: session.start))
                let wasDone = model.todayPlan().priorities.first { $0.id == priority.id }?.isDone == true
                HStack(spacing: 8) {
                    Image(systemName: wasDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(wasDone ? Theme.emerald : Color.secondary)
                    Text(wasDone
                         ? (isAllDone ? "Ticked off “\(priority.title)” — All study subjects completed! 🎉" : "Ticked off “\(priority.title)” 🎉")
                         : "“\(priority.title)” stays on today's list")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(wasDone ? Theme.emerald : Color.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Did you finish “\(priority.title)”?")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: Theme.Space.s) {
                    Button {
                        answer(priority, done: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text("Yes, it's done")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Not yet") { answer(priority, done: false) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func nextPrioritySection(_ next: Priority) -> some View {
        let subject = next.subjectID.flatMap(model.subject(id:)) ?? model.data.subjects.first
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundStyle(Theme.indigo)
                        .font(.system(size: 11))
                    Text("NEXT UP TODAY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.indigo)
                        .tracking(1)
                }
                Spacer()
                if next.isAnchor {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 8))
                        Text("Anchor").font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.amber.opacity(0.15)))
                }
                if let est = next.estimatedMinutes {
                    Text("\(est)m")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                if let subject {
                    let col = Theme.subjectColor(subject.colorHex)
                    HStack(spacing: 4) {
                        Circle().fill(col).frame(width: 5, height: 5)
                        Text(subject.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(col)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(col.opacity(0.12)))
                }
            }

            Text(next.title)
                .font(.system(size: 14, weight: .semibold))

            if let subject {
                HStack(spacing: Theme.Space.s) {
                    Button {
                        dismiss()
                        onStartNext?(subject, next)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                            Text("Lock in “\(next.title)”")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Menu {
                        ForEach([25, 50, 90], id: \.self) { mins in
                            Button("\(mins)m") {
                                model.selectActivePriority(next.id, for: subject.id, day: DayKey.key(for: session.start), notify: false)
                                dismiss()
                                Task { await model.lockIn(subjectID: subject.id, mode: .goal(minutes: mins)) }
                            }
                        }
                        Divider()
                        Button("Open-ended") {
                            model.selectActivePriority(next.id, for: subject.id, day: DayKey.key(for: session.start), notify: false)
                            dismiss()
                            Task { await model.lockIn(subjectID: subject.id, mode: .open) }
                        }
                    } label: {
                        Label("Quick", systemImage: "timer")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.indigo.opacity(0.10)))
                            .foregroundStyle(Theme.indigo)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 2)
            }
        }
        .padding(Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.indigo.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.indigo.opacity(0.2), lineWidth: 1))
        )
    }

    private func continueSubjectCard(_ subject: Subject) -> some View {
        let col = Theme.subjectColor(subject.colorHex)
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KEEP MOMENTUM GOING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(col)
                    .tracking(0.8)
                Text("Start another focus block on \(subject.name)")
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer()
            Menu {
                ForEach([25, 50, 90], id: \.self) { mins in
                    Button("\(mins)m") {
                        dismiss()
                        Task { await model.lockIn(subjectID: subject.id, mode: .goal(minutes: mins)) }
                    }
                }
                Divider()
                Button("Open-ended") {
                    dismiss()
                    Task { await model.lockIn(subjectID: subject.id, mode: .open) }
                }
            } label: {
                Label("Quick", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(col.opacity(0.14)))
                    .foregroundStyle(col)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                dismiss()
                onStartNext?(subject, nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Lock in again")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(col.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(col.opacity(0.22), lineWidth: 1))
        )
    }

    private func answer(_ priority: Priority, done: Bool) {
        model.setPriority(priority.id, done: done, day: DayKey.key(for: session.start))
        answered = true
    }

    private func copyMarkdownRecap() {
        let markdown = SessionSummaryText.markdownRecap(session: session, priority: priority, notes: notesText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        copiedMarkdown = true
        ToastCenter.shared.show("Markdown recap copied to clipboard")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            copiedMarkdown = false
        }
    }

    private func copyDiscordRecap() {
        let name = model.displayName
        let text: String
        if session.outcome == .bailed, let goal = session.mode.goalMinutes {
            text = DiscordMessages.bailed(name: name, subject: session.subjectName,
                                          duration: session.duration, goalMinutes: goal,
                                          attempts: session.blockedAttempts)
        } else {
            text = DiscordMessages.completed(name: name, subject: session.subjectName,
                                             duration: session.duration,
                                             attempts: session.blockedAttempts,
                                             tabs: session.closedTabs)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedDiscord = true
        ToastCenter.shared.show("Discord message copied to clipboard")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            copiedDiscord = false
        }
    }
}
