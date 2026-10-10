import SwiftUI

/// NavigationSplitView (sidebar + detail). When model.engine.isLocked shows LockedView(model:) full-window instead.
struct RootView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.engine.isLocked {
                LockedView(model: model)
            } else {
                NavigationSplitView {
                    SidebarView(model: model)
                } detail: {
                    detail
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case .subject(let id):
            if let subject = model.subject(id: id) {
                SubjectDetailView(model: model, subject: subject)
                    .id(subject.id)
            } else {
                emptyState
            }
        case .stats:
            StatsView(model: model)
        case .settings:
            SettingsView(model: model)
        case nil:
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Text("Pick a subject to lock in").font(.title3.weight(.semibold))
            Text(model.data.subjects.isEmpty ? "Add one with “Add subject” in the sidebar." : "Or open Stats and Settings.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
