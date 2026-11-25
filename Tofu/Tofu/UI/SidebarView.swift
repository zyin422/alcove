import SwiftUI

/// Subjects (with this week's time); an update card (when Sparkle found one), Stats, Settings and "Add subject" (⌘N) stay pinned at the bottom. Right-click deletes a subject.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingSubject = false
    @State private var subjectToDelete = Subject?.none
    @State private var lockInSubject: Subject?

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
                if model.data.subjects.isEmpty {
                    Text("No subjects yet. Add one to lock in.")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
                ForEach(model.data.subjects) { subject in
                    let counts = model.todayPriorityCounts(for: subject.id)
                    NavigationLink(value: SidebarItem.subject(subject.id)) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.subjectColor(subject.colorHex))
                                .frame(width: 8, height: 8)
                            Text(subject.name).lineLimit(1)
                            Spacer()
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
                        Button("Lock in “\(subject.name)”…") { lockInSubject = subject }
                        Button("Duplicate “\(subject.name)”") { model.duplicateSubject(id: subject.id) }
                        Divider()
                        Button("Delete “\(subject.name)”…", role: .destructive) { subjectToDelete = subject }
                    }
                }
                .onMove { source, destination in
                    withAnimation(.spring(duration: 0.22)) {
                        model.moveSubjects(from: source, to: destination)
                    }
                }
            } header: {
                Text("Subjects")
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
}
