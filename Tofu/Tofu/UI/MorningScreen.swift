import AppKit
import SwiftUI

/// Borderless windows can't become key by default, and the morning screen has text fields and buttons.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The full-screen "Good morning" window over the main screen. Shown and hidden through AppModel
/// (`onShowMorning` / `onHideMorning`).
@MainActor final class MorningWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard window == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .windowBackgroundColor
        window.contentView = NSHostingView(rootView: MorningView(model: model))
        window.setFrame(screen.frame, display: true)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Greeting, today's unfinished priorities as cards, and LOCK IN on the chosen one's setup.
struct MorningView: View {
    let model: AppModel
    @State private var selectedID: UUID?
    /// Setups chosen here for priorities that had none (or a different one).
    @State private var chosenSetups: [UUID: UUID] = [:]
    @State private var option: LockInOption = .minutes50
    @State private var customMinutes = 45
    @State private var newTitle = ""

    private var plan: DayPlan { model.todayPlan() }
    private var open: [Priority] { plan.priorities.filter { !$0.isDone } }
    private var selected: Priority? { open.first { $0.id == selectedID } ?? open.first }

    private func setupID(for priority: Priority) -> UUID? {
        let id = chosenSetups[priority.id] ?? priority.subjectID
        return id.flatMap(model.subject(id:)) == nil ? nil : id
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            VStack(spacing: Theme.Space.s) {
                BotAvatar(size: 64)
                Text("\(DayPlanner.greeting(at: Date())), \(firstName)")
                    .font(.system(size: 48, weight: .semibold))
                Text((DayKey.date(for: plan.day) ?? Date()).formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if model.data.settings.googleShowEventsEnabled,
               let events = model.googleSync?.todayEvents, !events.isEmpty {
                eventsBlock(events)
            }

            if open.isEmpty {
                emptyState
            } else {
                Text("What are you starting with?").font(.title2)
                VStack(spacing: Theme.Space.s) {
                    ForEach(open) { card($0) }
                }
                .frame(maxWidth: 560)
                startControls
            }
            Spacer()
            Button("Not now") { model.dismissMorning() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .padding(.bottom, Theme.Space.xl)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var firstName: String {
        model.displayName.split(separator: " ").first.map(String.init) ?? model.displayName
    }

    /// Read-only list of the first few of today's Google Calendar events.
    private func eventsBlock(_ events: [GoogleEvent]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Today's events").font(.headline)
            ForEach(events.prefix(5)) { event in
                HStack(spacing: Theme.Space.s) {
                    Text(GoogleEventFormat.timeLabel(event))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    Text(event.summary ?? "(untitled)")
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func card(_ priority: Priority) -> some View {
        let isSelected = selected?.id == priority.id
        return Button {
            selectedID = priority.id
        } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(priority.title).font(.title3.weight(.medium))
                    if let id = setupID(for: priority), let subject = model.subject(id: id) {
                        Text(subject.name).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("No setup yet").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(Theme.Space.m)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(Color.primary.opacity(isSelected ? 1 : 0.15), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var startControls: some View {
        if let priority = selected {
            VStack(spacing: Theme.Space.m) {
                if setupID(for: priority) == nil {
                    HStack {
                        Text("Setup for “\(priority.title)”").foregroundStyle(.secondary)
                        SetupPicker(subjects: model.data.subjects, selection: Binding(
                            get: { chosenSetups[priority.id] },
                            set: { chosenSetups[priority.id] = $0 }))
                            .frame(width: 180)
                    }
                    if model.data.subjects.isEmpty {
                        Text("Create a setup in the main window first.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Picker("Length", selection: $option) {
                    ForEach(LockInOption.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 420)
                if option == .custom {
                    Stepper("\(customMinutes) min", value: $customMinutes, in: LockInOption.customRange)
                        .fixedSize()
                }
                Button {
                    start(priority)
                } label: {
                    Text("LOCK IN").tracking(3).frame(width: 240, height: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
                .disabled(setupID(for: priority) == nil)
                .opacity(setupID(for: priority) == nil ? 0.35 : 1)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Text("No priorities for today yet. What's first?").font(.title2)
            HStack {
                TextField("e.g. Finish the CS128 lab", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(width: 420)
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let priority = Priority(title: title, subjectID: DayPlanner.matchSubject(title, subjects: model.data.subjects))
        model.updatePlan(day: plan.day) { $0.priorities.append(priority) }
        selectedID = priority.id
        newTitle = ""
    }

    private func start(_ priority: Priority) {
        guard let subjectID = setupID(for: priority) else { return }
        let mode = option.mode(customMinutes: customMinutes)
        let model = model
        Task { await model.start(priority: priority, subjectID: subjectID, mode: mode) }
    }
}
