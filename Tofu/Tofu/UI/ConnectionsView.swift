import SwiftUI

/// Connections: the Google account on top, then one card per service it feeds (Calendar, Tasks, Gmail), each
/// with its own switches and state. The only place Google is connected, disconnected or switched on and off.
struct ConnectionsView: View {
    let model: AppModel
    /// True while a Google sign-in is in flight, so Connect can't start a second one.
    @State private var isConnecting = false

    /// Width of a card's icon box; the switches line up with the text beside it.
    private static let iconSize: CGFloat = 36

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Connections").font(Theme.titleFont)
                    Text("Bring your calendar, tasks and mail into your day.").foregroundStyle(.secondary)
                }
                accountCard
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Services").font(Theme.captionFont).foregroundStyle(.secondary)
                    ForEach(GoogleService.allCases) { service in
                        serviceCard(service)
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Connections")
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                icon("person.crop.circle")
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Google account").font(.headline)
                    Text(accountLine).foregroundStyle(.secondary).textSelection(.enabled)
                    if !model.googleStatus.isEmpty {
                        Text(model.googleStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                accountButtons
            }
            Text("Sign-in shows “UIUC Collective Mind”, the shared Google app Tofu uses. If Google signs you out after a week, connect again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.iconSize + Theme.Space.m)
        }
        .connectionCard()
    }

    private var accountLine: String {
        guard model.isGoogleConnected else { return "Not connected" }
        if let email = model.data.settings.googleAccountEmail, !email.isEmpty { return "Connected as \(email)" }
        return "Connected"
    }

    @ViewBuilder private var accountButtons: some View {
        HStack(spacing: Theme.Space.s) {
            if isConnecting { ProgressView().controlSize(.small) }
            if model.isGoogleConnected {
                // Signing in again is the only way to add a scope, so it sits next to Disconnect, not on the cards.
                if model.googleNeedsReconnect {
                    Button("Reconnect…", action: connect)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isConnecting)
                }
                Button("Disconnect") { model.disconnectGoogle() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isConnecting)
            } else {
                Button("Connect…", action: connect)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isConnecting)
            }
        }
        .fixedSize()
    }

    /// Starts the Google sign-in; the buttons stay disabled until it finishes.
    private func connect() {
        isConnecting = true
        Task { @MainActor in
            await model.connectGoogle()
            isConnecting = false
        }
    }

    // MARK: - Services

    private func serviceCard(_ service: GoogleService) -> some View {
        let state = model.googleState(of: service)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                icon(service.symbol)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(service.title).font(.headline)
                    Text(service.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.m)
                StateBadge(state: state)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                switches(for: service)
                    .toggleStyle(.checkbox)
                    .disabled(!model.isGoogleConnected)
                if let detail = state.detail(for: service) ?? activity(for: service, state: state) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, Self.iconSize + Theme.Space.m)
        }
        .connectionCard()
        .opacity(model.isGoogleConnected ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(service.title), \(state.label)")
    }

    @ViewBuilder private func switches(for service: GoogleService) -> some View {
        switch service {
        case .calendar:
            Toggle("Show today's events on Today and the morning screen", isOn: setting(\.googleShowEventsEnabled))
            Toggle("Log finished sessions to the “Tofu” calendar", isOn: setting(\.googleSessionLogEnabled))
        case .tasks:
            Toggle("Mirror Today's priorities in Google Tasks", isOn: setting(\.googleTasksSyncEnabled))
        case .gmail:
            Toggle("Show unread Primary mail on Today", isOn: setting(\.googleGmailEnabled))
        }
    }

    /// A line showing the service is working ("3 events today"), when there is something to count.
    private func activity(for service: GoogleService, state: GoogleServiceState) -> String? {
        guard state == .on, let sync = model.googleSync else { return nil }
        switch service {
        case .calendar:
            guard model.data.settings.googleShowEventsEnabled else { return nil }
            switch sync.todayEvents.count {
            case 0: return "No events today"
            case 1: return "1 event today"
            case let count: return "\(count) events today"
            }
        case .tasks:
            return nil
        case .gmail:
            switch model.inboxMessages.count {
            case 0: return "No unread mail from the last 3 days"
            case 1: return "1 unread message from the last 3 days"
            case let count: return "\(count) unread messages from the last 3 days"
            }
        }
    }

    /// A switch bound to a Google setting. Turning one on syncs right away instead of on the next minute.
    private func setting(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.data.settings[keyPath: keyPath] },
                set: { newValue in
                    model.updateSettings { $0[keyPath: keyPath] = newValue }
                    if newValue { Task { await model.googleSync?.syncNow() } }
                })
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .frame(width: Self.iconSize, height: Self.iconSize)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius - 2).stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// "On", "Off", "Reconnect to enable" in a small outlined capsule. On is drawn in the label color, the rest gray.
private struct StateBadge: View {
    let state: GoogleServiceState

    var body: some View {
        let strong = state == .on || state == .notGranted
        Text(state.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(strong ? Color.primary : Color.secondary)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(strong ? Color.primary.opacity(0.6) : Color.primary.opacity(0.2), lineWidth: 1))
            .fixedSize()
    }
}

private extension View {
    /// The hairline-bordered box every card on Connections uses (the same border as StatCard).
    func connectionCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.m)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }
}
