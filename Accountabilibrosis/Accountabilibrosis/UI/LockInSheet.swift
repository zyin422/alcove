import SwiftUI

/// The session lengths offered when locking in.
enum LockInOption: Hashable, CaseIterable, Identifiable {
    case openEnded, minutes25, minutes50, minutes90, custom

    /// Stepper range for `custom`, in minutes (step 5).
    static let customRange = 5...240

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
        case .custom:
            let clamped = min(max(customMinutes, Self.customRange.lowerBound), Self.customRange.upperBound)
            return .goal(minutes: clamped)
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
            }

            Picker("Length", selection: $option) {
                ForEach(LockInOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if option == .custom {
                Stepper(value: $customMinutes, in: LockInOption.customRange, step: 5) {
                    Text("\(customMinutes) min").monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                note("Other apps will be hidden. Google Chrome, Finder\(subject.allowedApps.isEmpty ? "" : " and your allowed apps") stay available.")
                note(model.data.settings.discordEnabled
                     ? "Your Discord servers will see that you locked in."
                     : "Discord announcements are off (turn them on in Settings).")
                if option != .openEnded {
                    note("Ending before the goal means typing the give-up phrase.")
                }
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
