import AppKit
import SwiftUI

/// Today's unread Primary mail as a compact list: sender, subject, age. A row opens the message in Gmail on
/// the web. Read-only; the caller hides it when `messages` is empty (AppModel.inboxMessages is empty unless
/// Gmail is connected, on and granted).
struct InboxSection: View {
    let messages: [InboxMessage]
    /// The connected address (AppSettings.googleAccountEmail), so links open the right signed-in account.
    var account: String?
    /// Shown at most; the rest are counted under the list.
    var limit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Unread mail").font(.headline)
            // TimelineView keeps "5m" ages current while Today stays open.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(messages.prefix(limit)) { message in
                        row(message, now: context.date)
                    }
                    if messages.count > limit {
                        Text("\(messages.count - limit) more in Gmail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func row(_ message: InboxMessage, now: Date) -> some View {
        Button {
            if let url = message.webURL(account: account) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Text(message.senderName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Space.s)
                if let date = message.date {
                    Text(InboxFormat.age(of: date, now: now))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(message.snippet.isEmpty ? "Open in Gmail" : message.snippet)
        .accessibilityLabel("From \(message.senderName): \(message.subject)")
        .accessibilityHint("Opens the message in Gmail")
    }
}

/// Short ages for the inbox rows. Pure.
enum InboxFormat {
    /// "now", "12m", "3h", "2d" (future dates from clock skew count as now).
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}
