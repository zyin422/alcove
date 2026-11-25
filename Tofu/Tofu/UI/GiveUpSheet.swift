import SwiftUI

/// Context banner reminding the user of the focus block & priority at risk before bailing.
struct SessionStakeBanner: View {
    let model: AppModel

    var body: some View {
        let elapsed = model.engine.elapsed
        let activePriority: Priority? = model.engine.subject.flatMap { subject in
            let day = DayKey.key(for: Date())
            return model.plan(for: day)?.activePriority(for: subject.id)
        }
        let violations = (model.engine.session?.blockedAttempts ?? 0) + (model.engine.session?.closedTabs ?? 0)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.coral)
                Text("\(TimeFormat.short(elapsed)) invested in \(model.engine.subject?.name ?? "this block")")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                if let rem = model.engine.remaining {
                    Text("\(TimeFormat.short(rem)) left")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let activePriority {
                Text("Priority: \(activePriority.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(violations == 0 ? "Clean focus so far (0 deflections)" : "\(violations) shield \(violations == 1 ? "deflection" : "deflections") survived so far")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.coral.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.coral.opacity(0.22), lineWidth: 1))
    }
}

/// Offers a restorative 5-minute break instead of bailing once earned (>=25m focused).
struct SessionBreakOfferBanner: View {
    let model: AppModel
    let onDismissParent: () -> Void

    var body: some View {
        if model.engine.canTakeBreak && !model.engine.isOnBreak {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.emerald)
                        Text("Need to recharge instead of quitting?")
                            .font(.caption.weight(.semibold))
                    }
                    Text("You unlocked a 5-minute restorative break cleanly.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Take 5m Break") {
                    onDismissParent()
                    _ = model.engine.beginBreak(minutes: MirrorTurn.breakDefault)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.emerald)
                .controlSize(.small)
            }
            .padding(Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.emerald.opacity(0.12)))
        }
    }
}

/// Shared 2-minute Grace Pass banner surfaced in GiveUpSheet and MirrorSheet.
struct SessionGracePassBanner: View {
    let model: AppModel
    let onDismissParent: () -> Void

    var body: some View {
        if !model.engine.gracePassUsed && !model.engine.isOnGracePass {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.amber)
                        Text("Need to handle an urgent 2FA or task?")
                            .font(.caption.weight(.semibold))
                    }
                    Text("Take a 2-minute Grace Pass instead of bailing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("2m Grace Pass") {
                    onDismissParent()
                    model.engine.requestGracePass()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.amber)
                .controlSize(.small)
            }
            .padding(Theme.Space.s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.amber.opacity(0.12)))
        }
    }
}

/// Friction before bailing on a goal: the user must type the give-up phrase exactly
/// (case and surrounding whitespace ignored) before Bail is enabled.
struct GiveUpSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var isFieldFocused: Bool

    private var template: String { model.data.settings.giveUpTemplate }
    private var matches: Bool { model.engine.phraseMatches(typed, template: template) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("End early?")
                .font(.system(size: 20, weight: .semibold))
            Text("Ending early will be posted to Discord.")
                .foregroundStyle(.secondary)

            SessionStakeBanner(model: model)
            SessionBreakOfferBanner(model: model) { dismiss() }
            SessionGracePassBanner(model: model) { dismiss() }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Type this phrase to bail")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                Text(model.engine.giveUpPhrase(template: template))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1))
            }

            TextField("Give-up phrase", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($isFieldFocused)
                .onSubmit { bailIfMatches() }

            HStack(spacing: Theme.Space.s) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Bail") { bailIfMatches() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!matches)
                    .opacity(matches ? 1 : 0.35)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 420)
        .onAppear { isFieldFocused = true }
    }

    /// Ends the session as a bail once the phrase matches, then closes the sheet.
    private func bailIfMatches() {
        guard matches else { return }
        let engine = model.engine
        dismiss()
        Task { await engine.bail() }
    }
}
