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
    @Environment(\.dismiss) private var dismiss
    /// The priority this lock-in worked on, asked about once ("Did you finish …?").
    @State private var priority: Priority?
    @State private var answered = false

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
                    StatCard(title: "Duration", value: TimeFormat.short(session.duration))
                    if let goal = SessionSummaryText.goal(session.mode) {
                        StatCard(title: "Goal", value: goal)
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    StatCard(title: "Apps blocked", value: "\(session.blockedAttempts)")
                    StatCard(title: "Tabs closed", value: "\(session.closedTabs)")
                }
            }

            if let priority {
                priorityCheck(priority)
            }

            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.l)
        .frame(width: 420)
        .onAppear { priority = model.priorityToConfirm(after: session) }
    }

    @ViewBuilder private func priorityCheck(_ priority: Priority) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if answered {
                Label(model.todayPlan().priorities.first { $0.id == priority.id }?.isDone == true
                      ? "Ticked off “\(priority.title)”" : "“\(priority.title)” stays on today's list",
                      systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                Text("Did you finish “\(priority.title)”?")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: Theme.Space.s) {
                    Button("Yes, it's done") { answer(priority, done: true) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Not yet") { answer(priority, done: false) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }

    private func answer(_ priority: Priority, done: Bool) {
        model.setPriority(priority.id, done: done, day: DayKey.key(for: session.start))
        answered = true
    }
}
