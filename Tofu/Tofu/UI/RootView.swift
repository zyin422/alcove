import SwiftUI

private struct RootLockInRequest: Identifiable {
    let id = UUID()
    let subject: Subject
    let priority: Priority?
}

/// NavigationSplitView (sidebar + detail). When model.engine.isLocked shows LockedView(model:) full-window instead.
/// Presents SessionSummaryView once a session has ended (not when it was interrupted by quitting).
struct RootView: View {
    let model: AppModel
    @State private var summary: Session?
    @State private var lockInRequest: RootLockInRequest?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if model.engine.isLocked {
                LockedView(model: model)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(model: model)
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: model.engine.isLocked ? LockedLayout.chatMinWidth : 820,
               minHeight: model.engine.isLocked ? 400 : 560)
        .onChange(of: model.engine.lastEnded?.id) { _, _ in
            if let ended = model.engine.lastEnded, SessionSummaryText.shouldPresent(ended) {
                summary = ended
            }
        }
        .sheet(item: $summary) { ended in
            SessionSummaryView(model: model, session: ended, onStartNext: { nextSubject, nextPriority in
                lockInRequest = RootLockInRequest(subject: nextSubject, priority: nextPriority)
            })
        }
        .sheet(item: $lockInRequest) { request in
            LockInSheet(model: model, subject: request.subject, initialPriority: request.priority)
        }
        .sheet(isPresented: Binding(get: { model.isWrappingUpDay && !model.engine.isLocked && summary == nil },
                                    set: { if !$0 { model.isWrappingUpDay = false } })) {
            EndOfDayView(model: model)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case .today:
            TodayView(model: model)
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
