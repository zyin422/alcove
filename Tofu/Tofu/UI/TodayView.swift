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
                }
                .buttonStyle(.plain)
                .help(priority.isDone ? "Mark as not done" : "Mark as done")
            } else {
                Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(priority.isDone ? Color.primary : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(priority.title)
                    .strikethrough(priority.isDone)
                    .foregroundStyle(priority.isDone ? .secondary : .primary)
                if let subject = priority.subjectID.flatMap(model.subject(id:)) {
                    Text(subject.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canEdit {
                if !priority.isDone, let subject = priority.subjectID.flatMap(model.subject(id:)) {
                    Button("Lock in") { lockInSubject = subject }
                        .buttonStyle(SecondaryButtonStyle())
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

    private var addRow: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Add a priority", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            SetupPicker(subjects: model.data.subjects, selection: $newSubjectID)
                .frame(width: 160)
            Button("Add", action: add)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
