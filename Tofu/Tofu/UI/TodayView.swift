import SwiftUI

/// One day's priorities. The date is the title. Arrows step a day at a time and the calendar jumps to a past day.
/// The current day stays closed until the previous open day is wrapped up.
struct TodayView: View {
    let model: AppModel
    @State private var newTitle = ""
    @State private var newSubjectID: UUID?
    @State private var lockInSubject: Subject?
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
        Set(model.data.dayPlans.filter { $0.priorities.contains(where: \.isDone) }.map(\.day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                dayStepper
                Spacer(minLength: Theme.Space.m)
                MonthCalendar(month: month, today: todayKey, selected: shownDay, completedDays: completedDays,
                              onShiftMonth: { shiftMonth($0) }, onSelect: { showDay($0) })
            }

            forceBlockCountdownBanner

            let todaySessions = model.data.sessions.filter {
                DayKey.key(for: $0.start) == shownDay && !$0.isDemo
            }
            let events = (plan.day == todayKey && model.data.settings.googleShowEventsEnabled)
                ? (model.googleSync?.todayEvents ?? []) : []

            if !events.isEmpty || !todaySessions.isEmpty || !plan.priorities.isEmpty {
                TodayScheduleView(events: events, sessions: todaySessions, priorities: plan.priorities, day: shownDay, model: model, onLockIn: { subject in
                    lockInSubject = subject
                })
            }

            if plan.priorities.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(plan.priorities) { priority in
                        row(priority)
                        if priority.id != plan.priorities.last?.id { Divider() }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
            }

            if canEdit { addRow }

            Spacer()

            dayActions
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Today")
        .sheet(item: $lockInSubject) { subject in
            LockInSheet(model: model, subject: subject)
        }
    }

    @ViewBuilder private var forceBlockCountdownBanner: some View {
        if shownDay == todayKey,
           !model.engine.isLocked,
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
                        .foregroundStyle(Color.black)
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

    private var dayStepper: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            dayButton("chevron.left", help: "Previous day") { stepDay(-1) }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(heading).font(Theme.titleFont)
                Text(summary).foregroundStyle(.secondary)
            }
            dayButton("chevron.right", help: "Next day", enabled: canGoForward) { stepDay(1) }
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
        if currentDayIsBlocked || canEdit {
            HStack {
                if showsWrappedUp {
                    Label("Day wrapped up", systemImage: "moon.fill").foregroundStyle(.secondary)
                }
                Spacer()
                if currentDayIsBlocked || pendingDay != nil {
                    Button(currentDayIsBlocked ? "Wrap up the previous day" : "Wrap up this day") {
                        model.startMyDay()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("15m Planning") { Task { await model.startPlanningMode() } }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Start my day") { model.startMyDay() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(wrapUpButtonTitle) { model.isWrappingUpDay = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        } else if showsWrappedUp {
            Label("Day wrapped up", systemImage: "moon.fill").foregroundStyle(.secondary)
        }
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

    private func row(_ priority: Priority) -> some View {
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
                Text(priority.title)
                    .strikethrough(priority.isDone)
                    .foregroundStyle(priority.isDone ? .secondary : .primary)
                HStack(spacing: Theme.Space.xs) {
                    if let subject = priority.subjectID.flatMap(model.subject(id:)) {
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
                    durationBadge(for: priority)
                }
            }
            Spacer()
            if canEdit {
                if !priority.isDone, let subject = priority.subjectID.flatMap(model.subject(id:)) {
                    Button("Lock in") { lockInSubject = subject }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.indigo))
                        .foregroundStyle(Color.white)
                        .buttonStyle(.plain)
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

    private var addRow: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Add a priority (e.g. 8am CS128 lab 45m)", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            SetupPicker(subjects: model.data.subjects, selection: $newSubjectID)
                .frame(width: 160)
            Button("Add", action: add)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let raw = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let (title, estimatedMinutes, scheduledMinutes) = DayPlanner.parsePriorityDetails(from: raw)
        let subjectID = newSubjectID ?? DayPlanner.matchSubject(title, subjects: model.data.subjects)
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
    }
}

/// "No setup" or one of the subjects.
struct SetupPicker: View {
    let subjects: [Subject]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Setup", selection: $selection) {
            Text("No setup").tag(UUID?.none)
            ForEach(subjects) { subject in
                Text(subject.name).tag(UUID?.some(subject.id))
            }
        }
        .labelsHidden()
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
    var onLockIn: ((Subject) -> Void)? = nil

    @State private var hoveredBlockID: String?
    @State private var showingAllAgenda = false

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
            HStack {
                Text("Today's Schedule")
                    .font(.headline)
                Spacer()
                Text("\(events.count) events (\(TimeFormat.short(totalMeetingSeconds))) · \(totalPlannedMinutes)m planned · \(TimeFormat.short(totalFocusSeconds)) focused")
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
                            .fill(color.opacity(block.isDone ? 0.35 : 0.70))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color, lineWidth: hoveredBlockID == block.id ? 2 : 1)
                            )
                            .help("\(block.title) (\(block.timeRangeLabel))")
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
                .overlay(
                    // Current time red/accent vertical line across all 3 tracks
                    currentTimeLine(width: width)
                )
                .overlay(
                    // Next force block amber vertical line across all 3 tracks
                    nextForceBlockLine(width: width)
                )
            }
            .frame(height: 52)

            // Dynamic Hour Markers
            hourRuler

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
    private func currentTimeLine(width: CGFloat) -> some View {
        let nowF = layout.currentFraction()
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
                    if case .plannedPriority(_, let title, let subjectID, let isDone) = block.kind, !isDone {
                        let targetSubject = subjectID.flatMap(model.subject(id:))
                            ?? DayPlanner.matchSubject(title, subjects: model.data.subjects).flatMap(model.subject(id:))
                            ?? model.data.subjects.first
                        if let targetSubject {
                            Button("Lock in") {
                                onLockIn?(targetSubject)
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
