import SwiftUI

/// Subjects (with total time), then Stats and Settings. "+" adds a subject; right-click deletes one.
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
            Section {
                Label("Stats", systemImage: "chart.bar").tag(SidebarItem.stats)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .safeAreaInset(edge: .bottom) {
            Button {
                isAddingSubject = true
            } label: {
                Label("Add subject", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
            .help("Add subject (⌘N)")
            .padding(Theme.Space.m)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingSubject = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add subject")
            }
        }
        .sheet(isPresented: $isAddingSubject) {
            SubjectEditorView(model: model, subject: nil)
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

    /// Total time of the subject's finished sessions.
    private func totalTime(of subjectID: UUID) -> TimeInterval {
        model.data.sessions
            .filter { $0.subjectID == subjectID && $0.end != nil }
            .reduce(0) { $0 + $1.duration }
    }
}
