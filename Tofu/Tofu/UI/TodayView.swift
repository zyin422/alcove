import SwiftUI

private struct LockInTarget: Identifiable {
    let id = UUID()
    let subject: Subject
    var priority: Priority? = nil
    var suggestedMinutes: Int? = nil
}

/// One day's priorities. The date is the title. Arrows step a day at a time and the calendar jumps to a past day.
/// The current day stays closed until the previous open day is wrapped up.
struct TodayView: View {
    let model: AppModel
    @State private var newTitle = ""
    @State private var newSubjectID: UUID?
    @State private var userSelectedSubject = false
    @State private var lastAutoMatchedSubjectID: UUID?
    @State private var lockInTarget: LockInTarget?
    @State private var editingPriorityID: UUID?
    @State private var editingPriorityTitle = ""
    @State private var hideCompletedPriorities = false
    /// Nil shows the current day. Set when the user steps or jumps to a day.
    @State private var selectedDay: String?
    /// Nil follows the shown day's month. Set when the user pages the calendar or chooses a day.
    @State private var shownMonth: (year: Int, month: Int)?

    private var todayKey: String { DayKey.key(for: Date()) }
    /// The day on screen. Opens on the current day; arrows and the calendar move it.
    private var shownDay: String { selectedDay ?? todayKey }
    private var plan: DayPlan { model.plan(for: shownDay) ?? DayPlan(day: shownDay) }
    /// The day that still has to be wrapped up before the current day can start. Nil when the current day is open.
    private var pendingDay: String? { model.needsPreviousWrapUp() ? model.todayPlan().day : nil }
    /// Priorities can be changed on the pending day, or on the current day once nothing earlier is open.
    private var canEdit: Bool { shownDay == (pendingDay ?? todayKey) }
    /// The current day is on screen, but an earlier day was never wrapped up.
    private var currentDayIsBlocked: Bool { shownDay == todayKey && pendingDay != nil }
    /// A wrapped-up mark belongs to a day that was actually closed. It does not belong on the current day
    /// while an earlier day is still open, even if this date was marked during an older session.
    private var showsWrappedUp: Bool { plan.wrappedUp && !currentDayIsBlocked }
    /// "Again" only after this day on screen was wrapped up. The previous day's wrap-up does not count.
    private var wrapUpButtonTitle: String { plan.wrappedUp ? "Wrap up again" : "Wrap up" }
    private var canGoForward: Bool { shownDay < todayKey }
    private var month: (year: Int, month: Int) {
        if let shownMonth { return shownMonth }
        if let parts = DayKey.parts(of: shownDay) { return (parts.year, parts.month) }
        return (1970, 1)
    }
    private var completedDays: Set<String> {
        let priorityDays = Set(model.data.dayPlans.filter { $0.priorities.contains(where: \.isDone) }.map(\.day))
        let sessionDays = Set(model.data.sessions.filter { !$0.isDemo && $0.end != nil && $0.duration >= DayPlanner.realBlockSeconds }.map { DayKey.key(for: $0.start) })
        return priorityDays.union(sessionDays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    dayStepper
                    Spacer(minLength: Theme.Space.m)
                    MonthCalendar(month: month, today: todayKey, selected: shownDay, completedDays: completedDays,
                                  onShiftMonth: { shiftMonth($0) }, onSelect: { showDay($0) })
                }

                let momentum = FocusMomentumEngine.compute7DayMomentum(sessions: model.data.sessions)
                FocusMomentumBarView(
                    summary: momentum,
                    selectedDayKey: shownDay,
                    targetMinutes: model.data.settings.dailyTargetMinutes,
                    onSelectDay: { showDay($0) },
                    onUpdateTarget: { newTarget in
                        model.updateSettings { $0.dailyTargetMinutes = newTarget }
                        ToastCenter.shared.show("Daily focus goal set to \(newTarget / 60) hours 🎯")
                    }
                )

                subjectDistributionStripView

                forceBlockCountdownBanner
                bedtimeCountdownBanner

                let todaySessions = model.data.sessions.filter {
                    DayKey.key(for: $0.start) == shownDay && !$0.isDemo
                }
                let events = (plan.day == todayKey && model.data.settings.googleShowEventsEnabled)
                    ? (model.googleSync?.todayEvents ?? []) : []

                if !events.isEmpty || !todaySessions.isEmpty || !plan.priorities.isEmpty {
                    TodayScheduleView(
                        events: events,
                        sessions: todaySessions,
                        priorities: plan.priorities,
                        day: shownDay,
                        model: model,
                        onLockIn: { subject, priority in
                            lockInTarget = LockInTarget(subject: subject, priority: priority)
                        },
                        onLockInWindow: { window in
                            if let subject = topFocusSubject {
                                lockInTarget = LockInTarget(
                                    subject: subject,
                                    priority: topOpenPriority(for: subject.id),
                                    suggestedMinutes: window.suggestedBlockMinutes
                                )
                            }
                        }
                    )
                }

                if plan.priorities.isEmpty {
                    if canEdit {
                        dayKickoffHeroCard
                    } else {
                        Text(emptyMessage).foregroundStyle(.secondary)
                    }
                } else {
                    let openCount = plan.priorities.filter { !$0.isDone }.count
                    let doneCount = plan.priorities.count - openCount
                    let estimatedTotal = plan.priorities.filter { !$0.isDone }.compactMap(\.estimatedMinutes).reduce(0, +)
                    let visibleEntries = plan.priorities.enumerated().filter { !(hideCompletedPriorities && $0.element.isDone) }

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.s) {
                            Text("PRIORITIES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.6)
                            Text("· \(openCount) open")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if estimatedTotal > 0 {
                                Text("· ~\(TimeFormat.short(TimeInterval(estimatedTotal * 60)))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if doneCount > 0 {
                                Button {
                                    hideCompletedPriorities.toggle()
                                } label: {
                                    Text(hideCompletedPriorities ? "Show done (\(doneCount))" : "Hide done")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(hideCompletedPriorities ? Theme.indigo : .secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                            }
                            if canEdit && plan.priorities.count > 1 {
                                Menu {
                                    Button("Sort anchors & open first") {
                                        model.sortPrioritiesAnchorsFirst(day: plan.day)
                                    }
                                    if openCount > 0 {
                                        Button("Defer \(openCount) open to tomorrow") {
                                            _ = model.deferAllOpenPrioritiesToTomorrow(from: plan.day)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Priority actions")
                            }
                        }

                        if visibleEntries.isEmpty {
                            HStack {
                                Text("All \(doneCount) priorities done for this view.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Show done") { hideCompletedPriorities = false }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                            }
                            .padding(Theme.Space.m)
                            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.02)))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(visibleEntries, id: \.element.id) { index, priority in
                                    row(priority, index: index, count: plan.priorities.count)
                                    if priority.id != visibleEntries.last?.element.id { Divider() }
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                        }
                    }
                }

                if canEdit && !plan.priorities.isEmpty { addRow }

                if !todayParkedThoughtItems.isEmpty {
                    parkedThoughtsTriageCard
                }

                Spacer(minLength: Theme.Space.m)

                dayActions
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Plan")
        .sheet(item: $lockInTarget) { target in
            LockInSheet(
                model: model,
                subject: target.subject,
                initialPriority: target.priority,
                suggestedMinutes: target.suggestedMinutes
            )
        }
    }

    private var topFocusSubject: Subject? {
        let prioritized = plan.priorities.first { !$0.isDone && $0.isAnchor }?.subjectID
            ?? plan.priorities.first { !$0.isDone }?.subjectID
        return prioritized.flatMap(model.subject(id:)) ?? model.data.subjects.first
    }

    private func topOpenPriority(for subjectID: UUID) -> Priority? {
        plan.activePriority(for: subjectID)
    }

    @ViewBuilder private var forceBlockCountdownBanner: some View {
        if shownDay == todayKey,
           !model.engine.isLocked,
           !model.isStudyCompleted(day: todayKey),
           let deadline = model.nextForceBlockDeadline,
           let _ = model.secondsUntilNextForceBlock {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                HStack(spacing: Theme.Space.m) {
                    ZStack {
                        Circle()
                            .fill(Theme.amber.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: remaining <= 60 ? "exclamationmark.triangle.fill" : "timer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.amber)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Space.s) {
                            Text("NEXT FORCE LOCK-IN")
                                .font(Theme.captionFont)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.amber)
                            if let reason = model.nextForceBlockReason {
                                Text("• \(reason)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                            Text(TimeFormat.clock(remaining))
                                .font(Theme.timerFont(size: 24))
                                .fontWeight(.medium)
                                .foregroundStyle(remaining <= 60 ? Theme.coral : .primary)
                            Text("until mandatory lock-in")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        model.startMyDay()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.shield.fill")
                            Text("Lock In Now")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber))
                        .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.01))
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .fill(Theme.amber.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .stroke(Theme.amber.opacity(remaining <= 60 ? 0.6 : 0.25), lineWidth: remaining <= 60 ? 1.5 : 1)
                )
            }
        }
    }

    @ViewBuilder private var bedtimeCountdownBanner: some View {
        if shownDay == todayKey,
           !model.engine.isLocked,
           let midnight = DayPlanner.nextMidnightBedtime(after: Date(), bedtimeGuardEnabled: model.data.settings.bedtimeGuardEnabled) {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let remaining = max(0, midnight.timeIntervalSince(context.date))
                if remaining > 0 {
                    HStack(spacing: Theme.Space.m) {
                        ZStack {
                            Circle()
                                .fill(Theme.violet.opacity(0.18))
                                .frame(width: 34, height: 34)
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.violet)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NIGHTFALL SHIELD IN \(TimeFormat.clock(remaining))")
                                .font(Theme.captionFont.weight(.bold))
                                .foregroundStyle(Theme.violet)
                                .monospacedDigit()
                            Text("Bedtime guard locks screens automatically at 12:00 AM unless resting.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(Theme.Space.m)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.violet.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.violet.opacity(0.28), lineWidth: 1))
                }
            }
        }
    }

    private var dayStepper: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            dayButton("chevron.left", help: "Previous day") { stepDay(-1) }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(heading).font(Theme.titleFont)
                HStack(spacing: Theme.Space.m) {
                    Text(summary).foregroundStyle(.secondary)
                    dailyTargetDialView
                }
            }
            dayButton("chevron.right", help: "Next day", enabled: canGoForward) { stepDay(1) }
        }
    }

    private var totalFocusedSecondsForDay: TimeInterval {
        model.data.sessions.filter {
            DayKey.key(for: $0.start) == shownDay && !$0.isDemo && $0.outcome == .completed
        }.reduce(0) { $0 + $1.duration }
    }

    private var dailyTargetSeconds: TimeInterval {
        TimeInterval(model.data.settings.dailyTargetMinutes * 60)
    }

    private var focusProgressSummary: String {
        let focusedHours = totalFocusedSecondsForDay / 3600
        let targetHours = dailyTargetSeconds / 3600
        let percent = dailyTargetSeconds > 0 ? Int((totalFocusedSecondsForDay / dailyTargetSeconds) * 100) : 0
        if totalFocusedSecondsForDay >= dailyTargetSeconds && dailyTargetSeconds > 0 {
            return String(format: "%.1fh / %.0fh target (%d%%) · Met! 🎉", focusedHours, targetHours, percent)
        }
        let remainingSeconds = max(0, dailyTargetSeconds - totalFocusedSecondsForDay)
        let remainingHours = remainingSeconds / 3600
        return String(format: "%.1fh / %.0fh target (%d%%) · %.1fh left", focusedHours, targetHours, percent, remainingHours)
    }

    @ViewBuilder private var dailyTargetDialView: some View {
        let isMet = totalFocusedSecondsForDay >= dailyTargetSeconds && dailyTargetSeconds > 0
        let fraction = dailyTargetSeconds > 0 ? min(1.0, totalFocusedSecondsForDay / dailyTargetSeconds) : 0
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
                    .frame(width: 18, height: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(isMet ? Theme.emerald : Theme.indigo, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(-90))
                if isMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.emerald)
                }
            }

            VStack(alignment: .leading, spacing: 0.5) {
                HStack(spacing: 3) {
                    Text(isMet ? "TARGET MET" : "DAILY TARGET")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isMet ? Theme.emerald : Color.secondary)
                        .tracking(0.8)
                    if isMet {
                        Text("🎉")
                            .font(.system(size: 8.5))
                    }
                }
                Text(focusProgressSummary)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isMet ? Theme.emerald.opacity(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isMet ? Theme.emerald.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .help("Target: \(model.data.settings.dailyTargetMinutes / 60) hours of focused work per day (configurable in Settings)")
    }

    struct SubjectFocusShare: Identifiable {
        let id: String
        let name: String
        let seconds: TimeInterval
        let fraction: Double
        let color: Color
    }

    private var subjectFocusDistribution: [SubjectFocusShare] {
        let daySessions = model.data.sessions.filter {
            DayKey.key(for: $0.start) == shownDay && !$0.isDemo && $0.outcome == .completed
        }
        guard totalFocusedSecondsForDay > 0 else { return [] }
        var map: [String: TimeInterval] = [:]
        for s in daySessions {
            map[s.subjectName, default: 0] += s.duration
        }
        return map.map { name, seconds in
            let colorHex = model.data.subjects.first(where: { $0.name == name })?.colorHex ?? SubjectColor.hex(for: name)
            return SubjectFocusShare(
                id: name,
                name: name,
                seconds: seconds,
                fraction: seconds / totalFocusedSecondsForDay,
                color: Theme.subjectColor(colorHex)
            )
        }.sorted { $0.seconds > $1.seconds }
    }

    @ViewBuilder private var subjectDistributionStripView: some View {
        let shares = subjectFocusDistribution
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Subject Distribution")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(TimeFormat.short(totalFocusedSecondsForDay) + " focused")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    let width = geo.size.width
                    let totalSpacing = CGFloat(max(0, shares.count - 1)) * 2
                    let usableWidth = max(0, width - totalSpacing)
                    HStack(spacing: 2) {
                        ForEach(shares) { share in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(share.color)
                                .frame(width: max(4, usableWidth * CGFloat(share.fraction)))
                                .help("\(share.name): \(TimeFormat.short(share.seconds)) (\(Int(share.fraction * 100))%)")
                        }
                    }
                }
                .frame(height: 7)
                .clipShape(RoundedRectangle(cornerRadius: 3.5))

                HStack(spacing: Theme.Space.m) {
                    ForEach(shares) { share in
                        let subID = model.data.subjects.first(where: { $0.name == share.name })?.id
                        let chip = HStack(spacing: 4) {
                            Circle()
                                .fill(share.color)
                                .frame(width: 6, height: 6)
                            Text("\(share.name) (\(Int(share.fraction * 100))%)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        if let subID {
                            Button {
                                model.selection = .subject(subID)
                            } label: {
                                chip
                            }
                            .buttonStyle(.plain)
                            .help("Open \(share.name)")
                        } else {
                            chip
                        }
                    }
                    Spacer()
                }
            }
            .padding(Theme.Space.m)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func dayButton(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.25))
        .help(help)
    }

    /// "Tuesday, October 13". The same line is the only date on the page.
    private var heading: String {
        DayKey.date(for: shownDay)?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? shownDay
    }

    private var emptyMessage: String {
        if currentDayIsBlocked { return "Nothing starts here until the previous day is wrapped up." }
        if canEdit { return "No priorities yet. Add what you want to get done." }
        return "Nothing was planned this day."
    }

    private var summary: String {
        if currentDayIsBlocked, let pendingDay, let date = DayKey.date(for: pendingDay) {
            let name = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            return "Wrap up \(name) before starting this day."
        }
        if canEdit, pendingDay != nil { return "Wrap this day up before the next one starts." }
        let done = plan.priorities.filter(\.isDone).count
        if plan.priorities.isEmpty { return canEdit ? "Plan the day" : "Nothing completed" }
        if canEdit { return "\(done) of \(plan.priorities.count) done" }
        return "\(done) of \(plan.priorities.count) completed"
    }

    @ViewBuilder private var dayActions: some View {
        HStack {
            if showsWrappedUp {
                Label("Day wrapped up", systemImage: "moon.fill").foregroundStyle(.secondary)
            } else if model.isStudyCompleted(day: shownDay) {
                Label("All study subjects completed 🎉", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.emerald)
            }
            Spacer()

            Button {
                copyDailyRecap()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Recap")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Copy markdown summary of this day's focus time and priorities to clipboard")

            if currentDayIsBlocked || pendingDay != nil {
                Button(currentDayIsBlocked ? "Wrap up the previous day" : "Wrap up this day") {
                    model.startMyDay()
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if canEdit {
                if let topSubject = topFocusSubject, shownDay == todayKey {
                    let topPriority = topOpenPriority(for: topSubject.id)
                    Button {
                        lockInTarget = LockInTarget(subject: topSubject, priority: topPriority)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                            Text("Lock in (⌘L)")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut("l", modifiers: .command)
                    .help("Lock into \(topPriority?.title ?? topSubject.name)")
                }
                if model.canPlanToday {
                    Button("15m Planning") { Task { await model.startPlanningMode() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("Start my day") { model.startMyDay() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(wrapUpButtonTitle) { model.isWrappingUpDay = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func copyDailyRecap() {
        let dateString = DayKey.date(for: shownDay)?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? shownDay
        let todaySessions = model.data.sessions.filter {
            DayKey.key(for: $0.start) == shownDay && !$0.isDemo && $0.outcome == .completed
        }
        let totalSeconds = todaySessions.reduce(0) { $0 + $1.duration }
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let timeString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"

        var lines: [String] = []
        lines.append("## Focus Recap: \(dateString)")
        lines.append("- **Focused Time**: \(timeString) (\(todaySessions.count) session\(todaySessions.count == 1 ? "" : "s"))")

        if !plan.priorities.isEmpty {
            lines.append("- **Priorities**:")
            for p in plan.priorities {
                let check = p.isDone ? "✓" : "○"
                let subName = p.subjectID.flatMap(model.subject(id:))?.name
                let subTag = subName.map { " [\($0)]" } ?? ""
                let anchorTag = p.isAnchor ? " ⭐" : ""
                lines.append("  \(check)\(subTag)\(anchorTag) \(p.title)")
            }
        }

        let thoughts = model.data.sessions.filter { DayKey.key(for: $0.start) == shownDay }
            .flatMap(\.parkedThoughts)
        if !thoughts.isEmpty {
            lines.append("- **Parked Thoughts** (\(thoughts.count)):")
            for t in thoughts {
                lines.append("  - \(t)")
            }
        }

        let sessionNotes = todaySessions.compactMap { s -> (String, String)? in
            guard let n = s.notes, !n.isEmpty else { return nil }
            return (s.subjectName, n)
        }
        if !sessionNotes.isEmpty {
            lines.append("- **Session Notes**:")
            for (subj, note) in sessionNotes {
                lines.append("  - *\(subj)*: \(note)")
            }
        }

        let recapMarkdown = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recapMarkdown, forType: .string)
        ToastCenter.shared.show("Daily recap copied to clipboard 📋")
    }

    private func stepDay(_ delta: Int) {
        let next = delta < 0 ? DayKey.previous(shownDay) : DayKey.next(shownDay)
        showDay(next)
    }

    private func showDay(_ day: String) {
        guard !DayCalendar.isUpcoming(day, today: todayKey) else { return }
        selectedDay = day
        if let parts = DayKey.parts(of: day) { shownMonth = (parts.year, parts.month) }
    }

    private func shiftMonth(_ delta: Int) {
        shownMonth = DayCalendar.shiftMonth(year: month.year, month: month.month, by: delta)
    }

    private var todayParkedThoughtItems: [(sessionID: UUID, subjectName: String, subjectColor: String, index: Int, text: String)] {
        let sessions = model.data.sessions.filter { DayKey.key(for: $0.start) == shownDay && !$0.isDemo }
        var items: [(sessionID: UUID, subjectName: String, subjectColor: String, index: Int, text: String)] = []
        for session in sessions {
            let color = model.subject(id: session.subjectID)?.colorHex ?? "888888"
            for (idx, thought) in session.parkedThoughts.enumerated() {
                items.append((session.id, session.subjectName, color, idx, thought))
            }
        }
        return items
    }

    private var parkedThoughtsTriageCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Theme.amber)
                        .font(.system(size: 13))
                    Text("Parked Thoughts (\(todayParkedThoughtItems.count))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if canEdit && todayParkedThoughtItems.count > 1 {
                    Button("Convert all to Priorities") {
                        convertAllParkedThoughts()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(todayParkedThoughtItems.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: Theme.Space.s) {
                        Circle()
                            .fill(Theme.subjectColor(item.subjectColor))
                            .frame(width: 7, height: 7)

                        Text(item.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text("(\(item.subjectName))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if canEdit {
                            Button {
                                convertThoughtToPriority(item: item)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add to Plan")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.emerald)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.emerald.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help("Convert this parked thought into a priority on today's plan")

                            Button {
                                dismissThought(sessionID: item.sessionID, at: item.index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Dismiss thought")
                        }
                    }
                    .padding(Theme.Space.s)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.02))
                    )
                }
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func convertThoughtToPriority(item: (sessionID: UUID, subjectName: String, subjectColor: String, index: Int, text: String)) {
        let priority = ThoughtParkingEngine.promoteThoughtToPriority(
            thought: item.text,
            subjects: model.data.subjects
        )
        model.updatePlan(day: shownDay) { plan in
            plan.priorities.append(priority)
        }
        model.removeParkedThought(sessionID: item.sessionID, at: item.index)
        ToastCenter.shared.show("Converted to priority: \(priority.title) 🎯")
    }

    private func dismissThought(sessionID: UUID, at index: Int) {
        model.removeParkedThought(sessionID: sessionID, at: index)
    }

    private func convertAllParkedThoughts() {
        let items = todayParkedThoughtItems
        for item in items {
            let priority = ThoughtParkingEngine.promoteThoughtToPriority(
                thought: item.text,
                subjects: model.data.subjects
            )
            model.updatePlan(day: shownDay) { plan in
                plan.priorities.append(priority)
            }
        }
        model.clearParkedThoughts(day: shownDay)
        ToastCenter.shared.show("Converted \(items.count) thoughts to priorities 🎯")
    }

    private func row(_ priority: Priority, index: Int = 0, count: Int = 1) -> some View {
        HStack(spacing: Theme.Space.s) {
            if canEdit {
                Button {
                    model.setPriority(priority.id, done: !priority.isDone, day: plan.day)
                } label: {
                    Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(priority.isDone ? Theme.emerald : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(priority.isDone ? "Mark as not done" : "Mark as done")
            } else {
                Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(priority.isDone ? Theme.emerald : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                if canEdit && editingPriorityID == priority.id {
                    HStack(spacing: 6) {
                        TextField("Priority title", text: $editingPriorityTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { savePriorityTitleEdit(priority) }
                            .onExitCommand { editingPriorityID = nil }
                        Button("Save") { savePriorityTitleEdit(priority) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button {
                            editingPriorityID = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(priority.title)
                            .strikethrough(priority.isDone)
                            .foregroundStyle(priority.isDone ? .secondary : .primary)
                        if canEdit && !priority.isDone {
                            Button {
                                editingPriorityTitle = priority.title
                                editingPriorityID = priority.id
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Rename priority")
                        }
                    }
                }

                HStack(spacing: Theme.Space.xs) {
                    if canEdit && !priority.isDone {
                        prioritySubjectMenu(for: priority)
                    } else if let subject = priority.subjectID.flatMap(model.subject(id:)) {
                        let color = Theme.subjectColor(subject.colorHex)
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 5, height: 5)
                            Text(subject.name).font(.caption.weight(.semibold)).foregroundStyle(color)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12)))
                    }
                    if let scheduled = priority.scheduledTimeLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "clock").font(.system(size: 8))
                            Text(scheduled).font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(Theme.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.indigo.opacity(0.10)))
                    }
                    if priority.isAnchor {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 8))
                            Text("Anchor").font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.amber.opacity(0.15)))
                    }
                    if canEdit && !priority.isDone {
                        priorityDurationMenu(for: priority)
                    } else {
                        durationBadge(for: priority)
                    }
                }
            }
            Spacer()
            if canEdit {
                if !priority.isDone {
                    let subject = priority.subjectID.flatMap(model.subject(id:))
                        ?? DayPlanner.matchSubject(priority.title, subjects: model.data.subjects).flatMap(model.subject(id:))
                        ?? model.data.subjects.first
                    if let subject {
                        Button("Lock in") {
                            lockInTarget = LockInTarget(subject: subject, priority: priority)
                        }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.indigo))
                            .foregroundStyle(Color.white)
                            .buttonStyle(.plain)
                    }
                }

                if count > 1 {
                    HStack(spacing: 2) {
                        Button {
                            model.movePriority(from: index, to: index - 1, day: plan.day)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .foregroundStyle(index == 0 ? Color.secondary.opacity(0.3) : Color.secondary)
                        .help("Move priority up")

                        Button {
                            model.movePriority(from: index, to: index + 1, day: plan.day)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .disabled(index == count - 1)
                        .foregroundStyle(index == count - 1 ? Color.secondary.opacity(0.3) : Color.secondary)
                        .help("Move priority down")
                    }
                    .padding(.horizontal, 2)
                }

                if !priority.isDone {
                    Button {
                        model.togglePriorityAnchor(priority.id, day: plan.day)
                    } label: {
                        Image(systemName: priority.isAnchor ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(priority.isAnchor ? Theme.amber : Color.secondary)
                    .help(priority.isAnchor ? "Remove focus anchor" : "Set as primary focus anchor (⭐)")

                    Button {
                        model.deferPriorityToTomorrow(priority.id, from: plan.day)
                    } label: {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .help("Defer priority to tomorrow")
                }

                Button {
                    model.updatePlan(day: plan.day) { $0.priorities.removeAll { $0.id == priority.id } }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
    }

    private func savePriorityTitleEdit(_ priority: Priority) {
        model.updatePriorityDetails(priority.id, day: plan.day, title: editingPriorityTitle)
        editingPriorityID = nil
    }

    @ViewBuilder private func prioritySubjectMenu(for priority: Priority) -> some View {
        let current = priority.subjectID.flatMap(model.subject(id:))
        Menu {
            Button("No setup") {
                model.updatePriorityDetails(priority.id, day: plan.day, subjectID: .some(nil))
            }
            if !model.data.subjects.isEmpty {
                Divider()
                ForEach(model.data.subjects) { subject in
                    Button {
                        model.updatePriorityDetails(priority.id, day: plan.day, subjectID: .some(subject.id))
                    } label: {
                        if subject.id == priority.subjectID {
                            Label(subject.name, systemImage: "checkmark")
                        } else {
                            Text(subject.name)
                        }
                    }
                }
            }
        } label: {
            if let current {
                let color = Theme.subjectColor(current.colorHex)
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text(current.name).font(.caption.weight(.semibold)).foregroundStyle(color)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(color.opacity(0.75))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12)))
            } else {
                HStack(spacing: 3) {
                    Text("No setup").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.down").font(.system(size: 7)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
            }
        }
        .menuStyle(.borderlessButton)
        .help("Change assigned subject")
    }

    @ViewBuilder private func priorityDurationMenu(for priority: Priority) -> some View {
        let actualSeconds = model.focusDuration(for: priority, day: plan.day)
        let actualMinutes = Int(actualSeconds / 60)
        Menu {
            ForEach([15, 25, 45, 60, 90], id: \.self) { mins in
                Button {
                    model.updatePriorityDetails(priority.id, day: plan.day, estimatedMinutes: .some(mins))
                } label: {
                    if priority.estimatedMinutes == mins {
                        Label("\(mins)m", systemImage: "checkmark")
                    } else {
                        Text("\(mins)m")
                    }
                }
            }
            if priority.estimatedMinutes != nil {
                Divider()
                Button("Clear estimate") {
                    model.updatePriorityDetails(priority.id, day: plan.day, estimatedMinutes: .some(nil))
                }
            }
        } label: {
            if let estimated = priority.estimatedMinutes {
                HStack(spacing: 3) {
                    if priority.subjectID != nil { Text("·").font(.caption).foregroundStyle(.secondary) }
                    Text("\(actualMinutes)m / \(estimated)m")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(actualMinutes >= estimated ? Theme.emerald : .secondary)
                }
            } else if actualMinutes > 0 {
                Text("· \(actualMinutes)m focused · +Est")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("+ Est")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
            }
        }
        .menuStyle(.borderlessButton)
        .help("Set or update time estimate")
    }

    @ViewBuilder private func durationBadge(for priority: Priority) -> some View {
        let actualSeconds = model.focusDuration(for: priority, day: plan.day)
        let actualMinutes = Int(actualSeconds / 60)
        if let estimated = priority.estimatedMinutes {
            HStack(spacing: 4) {
                if priority.subjectID != nil { Text("·").font(.caption).foregroundStyle(.secondary) }
                Text("\(actualMinutes)m / \(estimated)m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(actualMinutes >= estimated ? Color.primary : Color.secondary)
            }
        } else if actualMinutes > 0 {
            HStack(spacing: 4) {
                if priority.subjectID != nil { Text("·").font(.caption).foregroundStyle(.secondary) }
                Text("\(actualMinutes)m focused")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dayKickoffHeroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .foregroundStyle(Theme.indigo)
                        .font(.system(size: 15, weight: .bold))
                    Text("What is your #1 focus today?")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Set your primary priority to focus your energy and start your day.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Theme.Space.s) {
                TextField("Add a priority (e.g. 9am CS128 lab 45m)", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: newTitle) { _, updated in
                        autoMatchDraftSetup(for: updated)
                    }
                SetupPicker(subjects: model.data.subjects, selection: draftSetupSelection)
                    .frame(width: 160)
                Button("Set Priority", action: add)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !model.data.subjects.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Quick subjects:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(model.data.subjects) { subject in
                            let color = Theme.subjectColor(subject.colorHex)
                            Button {
                                userSelectedSubject = true
                                newSubjectID = subject.id
                                if newTitle.isEmpty {
                                    newTitle = "Focus block: \(subject.name)"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(color).frame(width: 6, height: 6)
                                    Text(subject.name)
                                        .font(.caption2.weight(.medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(newSubjectID == subject.id ? color.opacity(0.2) : Color.primary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(newSubjectID == subject.id ? color : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(Theme.indigo.opacity(0.2), lineWidth: 1)
        )
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.s) {
                TextField("Add a priority (e.g. 8am CS128 lab 45m)", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: newTitle) { _, updated in
                        autoMatchDraftSetup(for: updated)
                    }
                SetupPicker(subjects: model.data.subjects, selection: draftSetupSelection)
                    .frame(width: 160)
                Button("Add", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 5) {
                Text("Duration:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach([15, 25, 45, 60, 90], id: \.self) { mins in
                    Button("\(mins)m") {
                        appendOrSetDuration(mins)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(Color.primary)
                    .buttonStyle(.plain)
                    .help("Set duration to \(mins) minutes")
                }
            }
        }
    }

    private func appendOrSetDuration(_ minutes: Int) {
        let pattern = #"\b\d+m\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(newTitle.startIndex..., in: newTitle)
            if regex.firstMatch(in: newTitle, options: [], range: range) != nil {
                newTitle = regex.stringByReplacingMatches(in: newTitle, options: [], range: range, withTemplate: "\(minutes)m")
                return
            }
        }
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        newTitle = trimmed.isEmpty ? "\(minutes)m" : "\(trimmed) \(minutes)m"
    }

    private var draftSetupSelection: Binding<UUID?> {
        Binding(
            get: { newSubjectID },
            set: { newValue in
                userSelectedSubject = true
                newSubjectID = newValue
            }
        )
    }

    private func autoMatchDraftSetup(for raw: String) {
        let (parsedTitle, _, _) = DayPlanner.parsePriorityDetails(from: raw)
        let next = DayPlanner.autoAssignedSubject(
            for: parsedTitle,
            currentSubjectID: newSubjectID,
            lastAutoMatchedID: lastAutoMatchedSubjectID,
            userOverrode: userSelectedSubject,
            subjects: model.data.subjects
        )
        newSubjectID = next.subjectID
        lastAutoMatchedSubjectID = next.autoMatchedID
    }

    private func add() {
        let raw = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let (title, estimatedMinutes, scheduledMinutes) = DayPlanner.parsePriorityDetails(from: raw)
        let subjectID = userSelectedSubject ? newSubjectID : (newSubjectID ?? DayPlanner.matchSubject(title, subjects: model.data.subjects))
        model.updatePlan(day: plan.day) {
            $0.priorities.append(Priority(
                title: title,
                subjectID: subjectID,
                estimatedMinutes: estimatedMinutes,
                scheduledMinutesFromMidnight: scheduledMinutes
            ))
        }
        newTitle = ""
        newSubjectID = nil
        userSelectedSubject = false
        lastAutoMatchedSubjectID = nil
    }
}

/// "No setup" or one of the subjects.
struct SetupPicker: View {
    let subjects: [Subject]
    @Binding var selection: UUID?

    private var selectedSubject: Subject? {
        subjects.first { $0.id == selection }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let selectedSubject {
                Circle()
                    .fill(Theme.subjectColor(selectedSubject.colorHex))
                    .frame(width: 7, height: 7)
            }
            Picker("Setup", selection: $selection) {
                Text("No setup").tag(UUID?.none)
                ForEach(subjects) { subject in
                    Text(subject.name).tag(UUID?.some(subject.id))
                }
            }
            .labelsHidden()
        }
    }
}

/// A compact month. Today is filled in. Days after today are gray and cannot be selected.
/// A dot marks a day with a completed priority.
private struct MonthCalendar: View {
    let month: (year: Int, month: Int)
    let today: String
    let selected: String
    let completedDays: Set<String>
    var onShiftMonth: (Int) -> Void
    var onSelect: (String) -> Void

    private var title: String {
        guard let date = Calendar.current.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else {
            return ""
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                shiftButton("chevron.left", help: "Previous month") { onShiftMonth(-1) }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                if selected != today || !isCurrentMonth {
                    Button("Today") { onSelect(today) }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.indigo.opacity(0.14)))
                        .foregroundStyle(Theme.indigo)
                        .buttonStyle(.plain)
                        .help("Jump back to today")
                }
                shiftButton("chevron.right", help: "Next month") { onShiftMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(DayCalendar.weekdayLabels().enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                }
                ForEach(DayCalendar.cells(year: month.year, month: month.month)) { cell in
                    dayCell(cell)
                }
            }
        }
        .padding(Theme.Space.s)
        .frame(width: 232)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }

    private var isCurrentMonth: Bool {
        guard let parts = DayKey.parts(of: today) else { return true }
        return month.year == parts.year && month.month == parts.month
    }

    private func shiftButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func dayCell(_ cell: DayCalendar.Cell) -> some View {
        let upcoming = DayCalendar.isUpcoming(cell.key, today: today)
        let isToday = cell.key == today
        let isSelected = cell.key == selected
        return Button {
            onSelect(cell.key)
        } label: {
            Text("\(cell.number)")
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .frame(width: 18, height: 18)
                .foregroundStyle(isToday ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .background {
                    if isToday {
                        Circle().fill(Color.primary)
                    } else if isSelected && !upcoming {
                        Circle().stroke(Color.primary, lineWidth: 1)
                    }
                }
                .overlay(alignment: .bottom) {
                    if completedDays.contains(cell.key) && !upcoming {
                        Circle().fill(Color.primary).frame(width: 3, height: 3).offset(y: 4)
                    }
                }
                .frame(width: 22, height: 18)
            .opacity(upcoming ? 0.3 : (cell.inMonth ? 1 : 0.4))
        }
        .buttonStyle(.plain)
        .disabled(upcoming)
        .accessibilityLabel(cell.key)
    }
}

/// Visual daily rhythm timeline combining calendar events, planned priorities, and completed focus sessions.
private struct TodayScheduleView: View {
    let events: [GoogleEvent]
    let sessions: [Session]
    let priorities: [Priority]
    let day: String
    let model: AppModel
    var onLockIn: ((Subject, Priority?) -> Void)? = nil
    var onLockInWindow: ((OpenFocusWindow) -> Void)? = nil

    @State private var hoveredBlockID: String?
    @State private var showingAllAgenda = false

    private var openWindows: [OpenFocusWindow] {
        DayPlanner.availableFocusWindows(
            calendarEvents: events,
            isToday: day == DayKey.key(for: Date())
        )
    }

    private var layout: DayScheduleLayout {
        DayPlanner.computeScheduleLayout(
            day: day,
            calendarEvents: events,
            priorities: priorities,
            sessions: sessions
        )
    }

    private var totalMeetingSeconds: TimeInterval {
        events.reduce(0) { total, event in
            guard let s = event.start.parsed, let e = event.end.parsed else { return total }
            return total + max(0, e.timeIntervalSince(s))
        }
    }

    private var totalPlannedMinutes: Int {
        priorities.reduce(0) { $0 + ($1.estimatedMinutes ?? 45) }
    }

    private var totalFocusSeconds: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Header stats
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Text("Today's Schedule")
                    .font(.headline)
                if day == DayKey.key(for: Date()),
                   let alert = DayPlanner.nextCalendarAlert(in: events, at: Date()) {
                    let urgent = !alert.isOngoing && alert.minutes <= 30
                    let tint: Color = alert.isOngoing ? Theme.cyan : (urgent ? Theme.amber : Theme.indigo)
                    HStack(spacing: 4) {
                        Image(systemName: alert.isOngoing ? "video.fill" : "bell.fill")
                            .font(.system(size: 9))
                        Text(alert.isOngoing
                             ? "Now: \(alert.title) (\(alert.minutes)m left)"
                             : "\(alert.title) in \(alert.minutes)m")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.14)))
                    .foregroundStyle(tint)
                }
                Spacer()
                let openMins = openWindows.reduce(0) { $0 + $1.durationMinutes }
                let openTag = (day == DayKey.key(for: Date()) && openMins > 0) ? " · \(TimeFormat.short(TimeInterval(openMins * 60))) open" : ""
                Text("\(events.count) events (\(TimeFormat.short(totalMeetingSeconds))) · \(totalPlannedMinutes)m planned · \(TimeFormat.short(totalFocusSeconds)) focused\(openTag)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Legend
            HStack(spacing: Theme.Space.m) {
                legendItem(title: "Calendar", color: Theme.cyan)
                legendItem(title: "Planned Focus", color: Theme.indigo)
                legendItem(title: "Completed", color: Theme.emerald)
                if model.nextForceBlockDeadline != nil {
                    legendItem(title: "Force Lock-In", color: Theme.amber)
                }
                Spacer()
            }

            // Multi-Track Timeline Bar
            TimelineView(.periodic(from: .now, by: 1.0)) { timelineContext in
                GeometryReader { geo in
                    let width = geo.size.width
                    VStack(spacing: 3) {
                        // Track 1: Calendar Events
                        trackRow(blocks: layout.calendarBlocks, width: width, height: 14) { block in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.cyan.opacity(0.35))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
                                .help("\(block.title) (\(block.timeRangeLabel))")
                        }

                        // Track 2: Planned Priorities
                        trackRow(blocks: layout.plannedBlocks, width: width, height: 16) { block in
                            let color = subjectColor(id: block.subjectID, name: block.title)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(block.hasConflict ? Theme.coral.opacity(0.85) : color.opacity(block.isDone ? 0.35 : 0.70))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(block.hasConflict ? Theme.coral : color, lineWidth: hoveredBlockID == block.id ? 2 : 1)
                                    )
                                    .overlay(alignment: .trailing) {
                                        if block.hasConflict {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 8))
                                                .foregroundStyle(Color.black)
                                                .padding(.trailing, 2)
                                        }
                                    }
                                    .help(block.hasConflict ? "⚠️ Conflict with \(block.conflictingEventTitle ?? "Meeting"): \(block.title) (\(block.timeRangeLabel))" : "\(block.title) (\(block.timeRangeLabel))")
                                    .onHover { isHovered in
                                        hoveredBlockID = isHovered ? block.id : nil
                                    }
                        }

                        // Track 3: Completed Focus Sessions
                        trackRow(blocks: layout.sessionBlocks, width: width, height: 14) { block in
                            let color = subjectColor(id: block.subjectID, name: block.title)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.emerald.opacity(0.4), lineWidth: 1))
                                .help("\(block.title) (\(block.timeRangeLabel))")
                        }
                    }
                    .overlay(alignment: .leading) {
                        // Current time red/accent vertical line across all 3 tracks
                        currentTimeLine(width: width, now: timelineContext.date)
                    }
                    .overlay(alignment: .leading) {
                        // Next force block amber vertical line across all 3 tracks
                        nextForceBlockLine(width: width)
                    }
                }
                .frame(height: 52)
            }

            // Dynamic Hour Markers
            hourRuler

            if !openWindows.isEmpty && day == DayKey.key(for: Date()) {
                openWindowsStrip
            }

            // Unified Chronological Agenda
            if !layout.chronologicalAgenda.isEmpty {
                agendaList
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.04)))
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func trackRow<Content: View>(
        blocks: [ScheduleBlock],
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: @escaping (ScheduleBlock) -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.04))
                .frame(height: height)

            ForEach(blocks) { block in
                let (startF, durF) = layout.fractions(startMinutes: block.startMinutes, endMinutes: block.endMinutes)
                content(block)
                    .frame(width: max(4, width * durF), height: height)
                    .offset(x: width * startF)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func currentTimeLine(width: CGFloat, now: Date = Date()) -> some View {
        let nowF = layout.currentFraction(now: now)
        if nowF >= 0 && nowF <= 1.0 {
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(width: 2, height: 52)
                .offset(x: width * nowF)
        }
    }

    @ViewBuilder
    private func nextForceBlockLine(width: CGFloat) -> some View {
        if let deadline = model.nextForceBlockDeadline,
           DayKey.key(for: deadline) == day {
            let cal = Calendar.current
            let mins = cal.component(.hour, from: deadline) * 60 + cal.component(.minute, from: deadline)
            let (f, _) = layout.fractions(startMinutes: mins, endMinutes: mins)
            if f >= 0 && f <= 1.0 {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Theme.amber)
                        .frame(width: 2, height: 52)
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 6, height: 6)
                        .offset(y: -4)
                }
                .offset(x: width * f)
                .help("Mandatory Lock-In at \(deadline.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    private var hourRuler: some View {
        let startH = Int(layout.dayStartHour)
        let endH = Int(layout.dayEndHour)
        let step = max(2, (endH - startH) / 6)
        let markers = stride(from: startH, through: endH, by: step).map { $0 }

        return HStack {
            ForEach(markers, id: \.self) { h in
                Text(formatHour(h))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if h != markers.last { Spacer() }
            }
        }
    }

    private var openWindowsStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.indigo)
                Text("CLEAR FOCUS WINDOWS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.indigo)
                    .tracking(0.6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(openWindows.prefix(3)) { window in
                        Button {
                            onLockInWindow?(window)
                        } label: {
                            HStack(spacing: 6) {
                                Text(window.timeRangeLabel)
                                    .font(.caption.weight(.medium).monospacedDigit())
                                Text("· \(window.durationMinutes)m clear")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("Lock \(window.suggestedBlockMinutes)m")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Theme.indigo.opacity(0.14)))
                                    .foregroundStyle(Theme.indigo)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.indigo.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Start a \(window.suggestedBlockMinutes)m focus block inside this \(window.durationMinutes)m gap")
                    }
                }
            }
        }
    }

    private func formatHour(_ h: Int) -> String {
        let normalized = (h % 24)
        let period = normalized >= 12 ? "PM" : "AM"
        let display = normalized == 0 ? 12 : (normalized > 12 ? normalized - 12 : normalized)
        return "\(display) \(period)"
    }

    private var agendaList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Day Agenda")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            let visibleCount = showingAllAgenda ? layout.chronologicalAgenda.count : 6
            ForEach(layout.chronologicalAgenda.prefix(visibleCount)) { block in
                HStack(spacing: Theme.Space.s) {
                    Text(block.timeRangeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 135, alignment: .leading)

                    switch block.kind {
                    case .calendarEvent:
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.cyan)
                        Text(block.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    case .plannedPriority(let priorityID, let title, let subjectID, let isDone):
                        Button {
                            model.setPriority(priorityID, done: !isDone, day: day)
                        } label: {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(isDone ? Theme.emerald : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .strikethrough(isDone)
                            .lineLimit(1)
                        if block.hasConflict {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                Text(block.conflictingEventTitle.map { "Conflict: \($0)" } ?? "Overlap")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Theme.coral)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.coral.opacity(0.15)))
                        }
                        if let subjectID, let subject = model.subject(id: subjectID) {
                            let color = Theme.subjectColor(subject.colorHex)
                            HStack(spacing: 3) {
                                Circle().fill(color).frame(width: 4, height: 4)
                                Text(subject.name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(color)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.14)))
                        }
                    case .completedSession(_, _, _, _):
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.emerald)
                        Text(block.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text("(\(block.durationMinutes)m)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Quick lock in for planned priority
                    if case .plannedPriority(let priorityID, let title, let subjectID, let isDone) = block.kind, !isDone {
                        let targetSubject = subjectID.flatMap(model.subject(id:))
                            ?? DayPlanner.matchSubject(title, subjects: model.data.subjects).flatMap(model.subject(id:))
                            ?? model.data.subjects.first
                        let matchedPriority = priorities.first(where: { $0.id == priorityID })
                        if let targetSubject {
                            Button("Lock in") {
                                onLockIn?(targetSubject, matchedPriority)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if layout.chronologicalAgenda.count > 6 {
                Button(showingAllAgenda ? "Show fewer items" : "Show \(layout.chronologicalAgenda.count - 6) more items") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showingAllAgenda.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }

    private func subjectColor(id: UUID?, name: String) -> Color {
        if let id, let subject = model.data.subjects.first(where: { $0.id == id }) {
            return Theme.subjectColor(subject.colorHex)
        }
        return Theme.subjectColor(SubjectColor.hex(for: name))
    }
}
