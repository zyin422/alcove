import SwiftUI

/// Pop-up card pinned above Stats in the sidebar when Sparkle found a newer version.
struct UpdateCard: View {
    let version: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Update available").font(Theme.captionFont).foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remind me later")
                .accessibilityLabel("Dismiss update")
            }
            Text("Tofu \(version)").font(.system(size: 13, weight: .semibold))
            Button(action: onUpdate) {
                Text("Update").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Download and install Tofu \(version)")
            .padding(.top, Theme.Space.xs)
        }
        .padding(Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}

#Preview {
    UpdateCard(version: "1.2", onUpdate: {}, onDismiss: {})
        .frame(width: 208)
        .padding()
}
