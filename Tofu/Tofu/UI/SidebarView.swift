import SwiftUI

/// Subjects (with this week's time); an update card (when Sparkle found one), Stats, Settings and "Add subject" (⌘N) stay pinned at the bottom. Right-click deletes a subject.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingSubject = false
    @State private var subjectToDelete = Subject?.none
    @State private var lockInSubject: Subject?
    @State private var subjectFilter = ""

    private var filteredSubjects: [Subject] {
        let query = subjectFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.data.subjects }
        return model.data.subjects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.details.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { model.selection },
            set: { newValue in
                if let newValue {
                    model.selection = newValue
                }
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                NavigationLink(value: SidebarItem.today) {
                    Label("Plan", systemImage: "checklist")
                }
            }
            Section {
                if model.data.subjects.count >= 5 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("Filter subjects", text: $subjectFilter)
                            .textFieldStyle(.plain)
                            .font(.caption)
                        if !subjectFilter.isEmpty {
                            Button {
                                subjectFilter = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .selectionDisabled()
                }
                if model.data.subjects.isEmpty {
                    Text("No subjects yet. Add one to lock in.")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(filteredSubjects) { subject in
                    let counts = model.todayPriorityCounts(for: subject.id)
                    let isActiveLock = model.engine.isLocked && model.engine.subject?.id == subject.id
                    NavigationLink(value: SidebarItem.subject(subject.id)) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.subjectColor(subject.colorHex))
                                .frame(width: 8, height: 8)
                            Text(subject.name).lineLimit(1)
                            Spacer()
                            if isActiveLock {
                                HStack(spacing: 3) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                    Text("LIVE")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.indigo.opacity(0.16)))
                                .foregroundStyle(Theme.indigo)
                            }
                            if counts.open > 0 {
                                Text("\(counts.open)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.indigo.opacity(0.14)))
                                    .foregroundStyle(Theme.indigo)
                                    .help("\(counts.open) open priorities today")
                            } else if counts.done > 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.emerald)
                                    .help("All \(counts.done) priorities done today")
                            }
                            Text(TimeFormat.short(totalTime(of: subject.id)))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Menu("Lock in “\(subject.name)”") {
                            ForEach([25, 50, 90], id: \.self) { mins in
                                Button("\(mins) min") {
                                    Task { await model.lockIn(subjectID: subject.id, mode: .goal(minutes: mins)) }
                                }
                            }
                            Divider()
                            Button("Choose Duration…") { lockInSubject = subject }
                        }
                        Button("Test Setup Workspace") {
                            Task { await model.previewWorkspace(for: subject) }
                        }
                        .disabled(model.engine.isLocked)
                        Divider()
                        Button("Duplicate “\(subject.name)”") { model.duplicateSubject(id: subject.id) }
                        Divider()
                        Button("Delete “\(subject.name)”…", role: .destructive) { subjectToDelete = subject }
                    }
                }
                .onMove { source, destination in
                    guard subjectFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    withAnimation(.spring(duration: 0.22)) {
                        model.moveSubjects(from: source, to: destination)
                    }
                }
            } header: {
                let weekTotal = model.data.subjects.reduce(0.0) { $0 + totalTime(of: $1.id) }
                HStack {
                    Text("Subjects")
                    Spacer()
                    if weekTotal > 0 {
                        Text(TimeFormat.short(weekTotal))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(SubjectHoursWindow.week.caption)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Space.xs) {
                if let version = model.updates.availableVersion {
                    UpdateCard(version: version,
                               onUpdate: { model.updates.checkNow() },
                               onDismiss: { model.updates.dismiss() })
                        .padding(.bottom, Theme.Space.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                todayProgressPill
                pinnedRow("Stats", systemImage: "chart.bar", item: .stats)
                pinnedRow("Settings", systemImage: "gearshape", item: .settings)
                Button {
                    isAddingSubject = true
                } label: {
                    Label("Add subject", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
                .help("Add subject (⌘N)")
                .padding(.top, Theme.Space.s)
            }
            .padding([.horizontal, .bottom], Theme.Space.m)
            .padding(.top, Theme.Space.s)
            .animation(.spring(duration: 0.35), value: model.updates.availableVersion)
        }
        .sheet(isPresented: $isAddingSubject) {
            SubjectEditorView(model: model)
        }
        .sheet(item: $lockInSubject) { subject in
            LockInSheet(model: model, subject: subject)
        }
        .confirmationDialog(
            "Delete “\(subjectToDelete?.name ?? "")”?",
            isPresented: Binding(get: { subjectToDelete != nil },
                                 set: { if !$0 { subjectToDelete = nil } }),
            titleVisibility: .visible,
            presenting: subjectToDelete
        ) { subject in
            Button("Delete") { model.deleteSubject(id: subject.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its past sessions stay in your stats.")
        }
    }

    /// A row pinned below the subject list; highlights like a List row when selected.
    private func pinnedRow(_ title: String, systemImage: String, item: SidebarItem) -> some View {
        Button {
            model.selection = item
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.s)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(model.selection == item ? Color.primary.opacity(0.1) : .clear)
        )
    }

    /// Hours for this subject in the current calendar week. Older weeks stay on the stats page.
    private func totalTime(of subjectID: UUID) -> TimeInterval {
        let stats = StatsEngine(now: max(model.engine.now, Date()))
        return stats.seconds(for: subjectID, in: model.data.sessions, window: .week)
    }

    private var todayProgressPill: some View {
        let dayKey = DayKey.key(for: max(model.engine.now, Date()))
        let focused = model.data.sessions
            .filter { $0.outcome == .completed && !$0.isDemo && DayKey.key(for: $0.start) == dayKey }
            .reduce(0.0) { $0 + $1.duration }
        let target = TimeInterval(max(1, model.data.settings.dailyTargetMinutes) * 60)
        let fraction = min(1.0, focused / target)
        let met = focused >= target

        return Button {
            model.selection = .today
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(TimeFormat.short(focused)) / \(TimeFormat.short(target))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(met ? Theme.emerald : .secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(met ? Theme.emerald : Theme.indigo)
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, Theme.Space.xs)
        .help("Today's focus toward daily target (\(model.data.settings.dailyTargetMinutes / 60)h)")
    }
}
