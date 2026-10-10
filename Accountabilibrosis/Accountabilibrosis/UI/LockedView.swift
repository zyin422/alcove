import SwiftUI

// PLACEHOLDER: Task 14 replaces this whole file with the real giant-timer screen.

/// Minimal locked screen: subject, timer and an End button (placeholder until Task 14).
struct LockedView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Text(model.engine.subject?.name ?? "")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(TimeFormat.clock(model.engine.remaining ?? model.engine.elapsed))
                .font(Theme.timerFont(size: 96))
            Button("End") {
                Task { await model.engine.finish() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
