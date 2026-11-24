import SwiftUI

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

    init(model: AppModel, subject: Subject) {
        self.model = model
        self.subject = subject
        _form = State(initialValue: SubjectFormState(subject: subject))
        _lastSaved = State(initialValue: subject)
    }

    var body: some View {
        let mastery = TechTreeEngine.computeMastery(
            for: subject,
            sessions: model.data.sessions,
            priorities: model.data.dayPlans.flatMap(\.priorities)
        )
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                TextField("Name", text: $form.name)
                    .textFieldStyle(.plain)
                    .font(Theme.titleFont)
                Button {
                    isChoosingMode = true
                } label: {
                    Text("LOCK IN")
                        .tracking(3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                masteryCard(mastery: mastery)
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
            LockInSheet(model: model, subject: subject)
        }
    }

    private func masteryCard(mastery: SubjectMastery) -> some View {
        let subjectColor = Theme.subjectColor(mastery.subject.colorHex)
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mastery.tier.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(subjectColor)
                    Text("• Level \(mastery.level)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("(\(mastery.xp) XP)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let nextTier = mastery.tier.next {
                    Text("\(Int(mastery.progressToNextTier * 100))% to \(nextTier.title) · \(String(format: "%.1f hrs", mastery.totalHours)) total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Grandmaster reached · \(String(format: "%.1f hrs", mastery.totalHours)) total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(mastery.unlockedBadges.prefix(4)) { badge in
                    Image(systemName: badge.systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(subjectColor)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(subjectColor.opacity(0.12)))
                        .help("\(badge.title): \(badge.description)")
                }
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    /// Saves the form whenever it is valid; an invalid draft keeps the last valid state saved.
    private func autosave() {
        guard form.errors.isEmpty else { return }
        let updated = form.subject(id: subject.id, createdAt: subject.createdAt)
        guard updated != lastSaved else { return }
        lastSaved = updated
        model.updateSubject(updated)
    }
}
