import SwiftUI

/// Today's priorities: tick them off, add or remove them, lock in on one, and end the day.
struct TodayView: View {
    let model: AppModel
    @State private var newTitle = ""
    @State private var newSubjectID: UUID?
    @State private var lockInSubject: Subject?

    private var plan: DayPlan { model.todayPlan() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Today").font(Theme.titleFont)
                Text(summary).foregroundStyle(.secondary)
            }

            if plan.priorities.isEmpty {
                Text("No priorities yet. Add what you want to get done today.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(plan.priorities) { priority in
                        row(priority)
                        if priority.id != plan.priorities.last?.id { Divider() }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
            }

            addRow

            Spacer()

            HStack {
                if plan.wrappedUp {
                    Label("Day wrapped up", systemImage: "moon.fill").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start my day") { model.startMyDay() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(plan.wrappedUp ? "Wrap up again" : "End my day") { model.isWrappingUpDay = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Post day recap") { model.postDayRecap() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Today")
        .sheet(item: $lockInSubject) { subject in
            LockInSheet(model: model, subject: subject)
        }
    }

    private var summary: String {
        let done = plan.priorities.filter(\.isDone).count
        return plan.priorities.isEmpty ? "Plan your day" : "\(done) of \(plan.priorities.count) done"
    }

    private func row(_ priority: Priority) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                model.setPriority(priority.id, done: !priority.isDone, day: plan.day)
            } label: {
                Image(systemName: priority.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help(priority.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(priority.title)
                    .strikethrough(priority.isDone)
                    .foregroundStyle(priority.isDone ? .secondary : .primary)
                if let subject = priority.subjectID.flatMap(model.subject(id:)) {
                    Text(subject.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
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
