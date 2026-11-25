import SwiftUI

/// The session lengths offered when locking in.
enum LockInOption: Hashable, CaseIterable, Identifiable {
    case openEnded, minutes25, minutes50, minutes90, custom

    /// Allowed range for `custom`, in minutes. The floor is a real block, so a finished timer always counts.
    static var customRange: ClosedRange<Int> {
        let floor = max(1, Int(DayPlanner.realBlockSeconds / 60))
        return floor...240
    }

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

    /// Suggests the matching option and custom duration for a given estimated minutes count.
    static func suggestedOption(for estimatedMinutes: Int?) -> (option: LockInOption, customMinutes: Int)? {
        guard let minutes = estimatedMinutes, minutes > 0 else { return nil }
        if minutes == 25 { return (.minutes25, 25) }
        if minutes == 50 { return (.minutes50, 50) }
        if minutes == 90 { return (.minutes90, 90) }
        return (.custom, clampedMinutes(minutes))
    }
}

/// Summary of what a subject launches when locking in (unit-tested).
struct LockInWorkspaceSummary: Equatable {
    let layoutLabel: String
    let browserTitle: String
    let urlCount: Int
    let appNames: [String]
    let unusedPolicyLabel: String
    let trustedDomains: [String]

    static func describe(subject: Subject) -> LockInWorkspaceSummary {
        let layoutLabel = subject.usesCustomLayout ? "Custom layout" : subject.preset.title
        let urlCount = subject.slots.filter { $0.kind == .website }.flatMap(\.urls).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let appNames = subject.slotApps.map(\.name) + subject.allowedApps.map(\.name)
        let dedupApps = Array(NSOrderedSet(array: appNames)) as? [String] ?? appNames
        let domains = (subject.sites + subject.extraDomains)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return LockInWorkspaceSummary(
            layoutLabel: layoutLabel,
            browserTitle: subject.browser.title,
            urlCount: urlCount,
            appNames: dedupApps,
            unusedPolicyLabel: subject.unusedApps == .quit ? "Quit other apps" : "Hide other apps",
            trustedDomains: Array(Set(domains)).sorted()
        )
    }
}

/// Mode choice before locking in: open-ended or a goal, then LOCK IN.
struct LockInSheet: View {
    let model: AppModel
    let subject: Subject
    var initialPriority: Priority? = nil
    var suggestedMinutes: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var option: LockInOption = .openEnded
    @State private var customMinutes = 45
    @State private var selectedPriorityID: UUID?

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

            if let priority = activePriority {
                targetPriorityBanner(priority)
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

            workspacePreviewCard

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                note(model.data.settings.discordEnabled
                     ? "Your Discord servers will see that you locked in."
                     : "Discord announcements are off (turn them on in Settings).")
                note("Ending the session opens the Mirror first. It asks whether you are stuck or choosing to stop.")
                note("Quitting Tofu is off until the block ends. Force Quit brings the block back.")
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
        .onAppear {
            if let initial = initialPriority, !initial.isDone {
                selectedPriorityID = initial.id
            } else {
                selectedPriorityID = model.todayPlan().activePriority(for: subject.id)?.id
            }
            if let suggestedMinutes, suggestedMinutes > 0 {
                applyEstimated(suggestedMinutes)
            } else if let est = activePriority?.estimatedMinutes {
                applyEstimated(est)
            }
        }
    }

    private var subjectPriorities: [Priority] {
        model.todayPlan().priorities.filter { $0.subjectID == subject.id && !$0.isDone }
    }

    private var activePriority: Priority? {
        if let selectedPriorityID,
           let matched = subjectPriorities.first(where: { $0.id == selectedPriorityID }) {
            return matched
        }
        return initialPriority.flatMap { $0.isDone ? nil : $0 } ?? model.todayPlan().activePriority(for: subject.id)
    }

    private func targetPriorityBanner(_ priority: Priority) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: priority.isAnchor ? "star.fill" : "target")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(priority.isAnchor ? Theme.amber : Theme.subjectColor(subject.colorHex))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(priority.isAnchor ? "FOCUS ANCHOR" : "TARGET PRIORITY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(priority.isAnchor ? Theme.amber : Theme.subjectColor(subject.colorHex))
                    if let est = priority.estimatedMinutes {
                        Text("· \(est)m planned")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if subjectPriorities.count > 1 {
                        Menu {
                            ForEach(subjectPriorities) { item in
                                Button {
                                    selectedPriorityID = item.id
                                    if let est = item.estimatedMinutes {
                                        applyEstimated(est)
                                    }
                                } label: {
                                    if item.id == priority.id {
                                        Label(item.title, systemImage: "checkmark")
                                    } else {
                                        Text(item.title)
                                    }
                                }
                            }
                        } label: {
                            Text("Switch (\(subjectPriorities.count))")
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .menuStyle(.borderlessButton)
                        .help("Pick which priority for \(subject.name) this session targets")
                    }
                }
                Text(priority.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            if let est = priority.estimatedMinutes, est > 0 {
                Button("Match \(est)m") {
                    applyEstimated(est)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(priority.isAnchor ? Theme.amber.opacity(0.35) : Theme.subjectColor(subject.colorHex).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func applyEstimated(_ est: Int) {
        if let suggestion = LockInOption.suggestedOption(for: est) {
            option = suggestion.option
            customMinutes = suggestion.customMinutes
        }
    }

    private var workspacePreviewCard: some View {
        let info = LockInWorkspaceSummary.describe(subject: subject)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subjectColor(subject.colorHex))
                    Text("Workspace Launch")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Text("\(info.layoutLabel) · \(info.browserTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Space.s) {
                Text(info.urlCount > 0 ? "\(info.urlCount) start \(info.urlCount == 1 ? "tab" : "tabs")" : "Clean browser")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(info.unusedPolicyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !info.appNames.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text("Apps: \(info.appNames.prefix(3).joined(separator: ", "))\(info.appNames.count > 3 ? " +\(info.appNames.count - 3)" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !info.trustedDomains.isEmpty {
                Text("Trusted domains: \(info.trustedDomains.prefix(4).joined(separator: ", "))\(info.trustedDomains.count > 4 ? " +\(info.trustedDomains.count - 4)" : "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Closes the sheet first so the window is free to move, then starts the session.
    private func lockIn() {
        if let priority = activePriority {
            model.selectActivePriority(priority.id, for: subject.id, day: model.todayPlan().day, notify: false)
        }
        let mode = option.mode(customMinutes: customMinutes)
        let subjectID = subject.id
        let subjectName = subject.name
        let model = model
        dismiss()
        VoiceOutput.shared.speak("Locked in with \(subjectName). Stay focused.")
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
            Text("min, at least \(LockInOption.customRange.lowerBound)")
                .foregroundStyle(.secondary)
        }
    }

    private var typed: Binding<Int> {
        Binding(get: { minutes },
                set: { minutes = LockInOption.clampedMinutes($0) })
    }
}
