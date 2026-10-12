import SwiftUI

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
