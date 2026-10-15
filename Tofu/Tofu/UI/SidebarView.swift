import SwiftUI

/// Subjects (with total time); Stats, Settings and "Add subject" (⌘N) stay pinned at the bottom. Right-click deletes a subject.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var isAddingSubject = false
    @State private var subjectToDelete: Subject?

    var body: some View {
        List(selection: $model.selection) {
            Section {
                Label("Today", systemImage: "checklist").tag(SidebarItem.today)
            }
            Section("Subjects") {
                if model.data.subjects.isEmpty {
                    Text("No subjects yet. Add one to lock in.")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                } else {
                    ForEach(model.data.subjects) { subject in
                        HStack {
                            Text(subject.name).lineLimit(1)
                            Spacer()
                            Text(TimeFormat.short(totalTime(of: subject.id)))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.subject(subject.id))
                        .contextMenu {
                            Button("Delete “\(subject.name)”…") { subjectToDelete = subject }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Space.xs) {
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
        }
        .sheet(isPresented: $isAddingSubject) {
            SubjectEditorView(model: model)
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

    /// Total time of the subject's finished sessions.
    private func totalTime(of subjectID: UUID) -> TimeInterval {
        model.data.sessions
            .filter { $0.subjectID == subjectID && $0.end != nil }
            .reduce(0) { $0 + $1.duration }
    }
}
