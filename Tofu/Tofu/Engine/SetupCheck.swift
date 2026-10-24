import Foundation

/// The "Setup check" at the top of Settings: one line per thing a lock-in depends on, so a missing permission
/// or key is visible before it silently weakens a session. Pure; SettingsView supplies the inputs.
struct SetupCheck: Equatable {
    enum State: Equatable {
        case ready
        /// Works, with a limitation the user may accept (no OpenAI key: unsure sites are asked about instead).
        case optional
        case needsAction
        /// Not known yet (e.g. Chrome isn't running, so macOS can't say).
        case unknown
    }

    struct Item: Equatable, Identifiable {
        var id: String { title }
        var title: String
        var state: State
        var detail: String
    }

    struct Inputs: Equatable {
        var accessibility: Bool
        var chrome: AutomationPermission
        var openAIKey: TokenSource
        var discordEnabled: Bool
        var discordToken: TokenSource
        var googleConnected: Bool
    }

    static func items(_ inputs: Inputs) -> [Item] {
        [
            Item(title: "Accessibility",
                 state: inputs.accessibility ? .ready : .needsAction,
                 detail: inputs.accessibility ? "Windows can be placed"
                    : "Needed to place app and Arc windows — see Window placement below"),
            chromeItem(inputs.chrome),
            Item(title: "OpenAI key",
                 state: inputs.openAIKey == .none ? .optional : .ready,
                 detail: inputs.openAIKey == .none ? "No key: you're asked about each new site instead"
                    : "Off-task tabs are judged automatically"),
            discordItem(enabled: inputs.discordEnabled, token: inputs.discordToken),
            Item(title: "Google",
                 state: inputs.googleConnected ? .ready : .optional,
                 detail: inputs.googleConnected ? "Tasks and Calendar sync" : "Not connected (optional)"),
        ]
    }

    /// "4 of 5 ready". Optional items count as ready; unknown ones don't.
    static func summary(_ items: [Item]) -> String {
        let ready = items.filter { $0.state == .ready || $0.state == .optional }.count
        return "\(ready) of \(items.count) ready"
    }

    private static func chromeItem(_ permission: AutomationPermission) -> Item {
        switch permission {
        case .allowed:
            return Item(title: "Chrome control", state: .ready, detail: "Study sites open and off-task tabs close")
        case .denied:
            return Item(title: "Chrome control", state: .needsAction,
                        detail: "Denied — allow Tofu in System Settings › Privacy & Security › Automation")
        case .notAsked:
            return Item(title: "Chrome control", state: .needsAction, detail: "Not allowed yet — use Request access below")
        case .appNotRunning:
            return Item(title: "Chrome control", state: .unknown, detail: "Open Chrome to check")
        case .notInstalled:
            return Item(title: "Chrome control", state: .needsAction,
                        detail: "Google Chrome isn't installed: no sites open and no tabs are watched")
        }
    }

    private static func discordItem(enabled: Bool, token: TokenSource) -> Item {
        guard enabled else { return Item(title: "Discord", state: .optional, detail: "Announcements are off") }
        if token == .none {
            return Item(title: "Discord", state: .needsAction, detail: "Announcements are on but there is no bot token")
        }
        return Item(title: "Discord", state: .ready, detail: token.label)
    }
}
