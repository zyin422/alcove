import SwiftUI

/// Text and presentation rules for the end-of-session summary (unit-tested).
enum SessionSummaryText {
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
}

/// Sheet shown after a session ends (spec §6, end step 5): subject, outcome, time, counters and the goal.
struct SessionSummaryView: View {
    let model: AppModel
    let session: Session
    var onStartNext: ((Subject) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// The priority this lock-in worked on, asked about once ("Did you finish …?").
    @State private var priority: Priority?
    @State private var answered = false
    @State private var addedThoughtsToPlan = false

    var body: some View {
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
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    StatCard(title: "Apps blocked", value: "\(session.blockedAttempts)", tint: session.blockedAttempts > 0 ? Theme.rose : nil, icon: "shield.fill")
                    StatCard(title: "Tabs closed", value: "\(session.closedTabs)", tint: session.closedTabs > 0 ? Theme.rose : nil, icon: "xmark.circle.fill")
                }
            }

            Button {
                copyDiscordRecap()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Copy Discord Message")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)

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
            }

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.l)
        .frame(width: 460)
        .onAppear { priority = model.priorityToConfirm(after: session) }
        .onDisappear { model.engine.applyRelaunch() }
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
                    let priorities = ThoughtParkingEngine.formatAsPriorities(thoughts: session.parkedThoughts, subjectID: session.subjectID)
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
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Bring back")
                .font(.system(size: 15, weight: .semibold))
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
                Button {
                    dismiss()
                    onStartNext?(subject)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                        Text("Lock in “\(next.title)”")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
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

    private func answer(_ priority: Priority, done: Bool) {
        model.setPriority(priority.id, done: done, day: DayKey.key(for: session.start))
        answered = true
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
        ToastCenter.shared.show("Discord message copied to clipboard")
    }
}
