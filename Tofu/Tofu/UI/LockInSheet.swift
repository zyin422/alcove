import SwiftUI

/// The session lengths offered when locking in.
enum LockInOption: Hashable, CaseIterable, Identifiable {
    case openEnded, minutes25, minutes50, minutes90, custom

    /// Allowed range for `custom`, in minutes.
    static let customRange = 1...240

    /// `minutes` limited to `customRange`.
    static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, customRange.lowerBound), customRange.upperBound)
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .openEnded: return "Open-ended"
        case .minutes25: return "25 min"
        case .minutes50: return "50 min"
        case .minutes90: return "90 min"
        case .custom: return "Custom"
        }
    }

    /// Session mode for this option; `customMinutes` is clamped to `customRange`.
    func mode(customMinutes: Int) -> SessionMode {
        switch self {
        case .openEnded: return .open
        case .minutes25: return .goal(minutes: 25)
        case .minutes50: return .goal(minutes: 50)
        case .minutes90: return .goal(minutes: 90)
        case .custom: return .goal(minutes: Self.clampedMinutes(customMinutes))
        }
    }
}

/// Mode choice before locking in: open-ended or a goal, then LOCK IN.
struct LockInSheet: View {
    let model: AppModel
    let subject: Subject
    @Environment(\.dismiss) private var dismiss
    @State private var option: LockInOption = .openEnded
    @State private var customMinutes = 45

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Lock in").font(Theme.captionFont).foregroundStyle(.secondary)
                Text(subject.name).font(Theme.titleFont).lineLimit(1)
                if !subject.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subject.details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker("Length", selection: $option) {
                ForEach(LockInOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if option == .custom {
                CustomMinutesField(minutes: $customMinutes)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                note("Other apps will be hidden. Google Chrome, Finder\(subject.allowedApps.isEmpty ? "" : " and your allowed apps") stay available.")
                note("Tabs unrelated to \(subject.name) are closed automatically (checked by AI).")
                note(model.data.settings.discordEnabled
                     ? "Your Discord servers will see that you locked in."
                     : "Discord announcements are off (turn them on in Settings).")
                note("Ending the session opens the Mirror first. It asks whether you are stuck or choosing to stop.")
            }

            HStack(spacing: Theme.Space.m) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    lockIn()
                } label: {
                    Text("LOCK IN").tracking(2)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 180)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Closes the sheet first so the window is free to move, then starts the session.
    private func lockIn() {
        let mode = option.mode(customMinutes: customMinutes)
        let subjectID = subject.id
        let model = model
        dismiss()
        Task { await model.lockIn(subjectID: subjectID, mode: mode) }
    }
}

/// A small box for a custom lock-in length. The typed number is kept inside `LockInOption.customRange`.
struct CustomMinutesField: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TextField("Minutes", value: typed, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .accessibilityLabel("Minutes")
            Text("min").foregroundStyle(.secondary)
        }
    }

    private var typed: Binding<Int> {
        Binding(get: { minutes },
                set: { minutes = LockInOption.clampedMinutes($0) })
    }
}
