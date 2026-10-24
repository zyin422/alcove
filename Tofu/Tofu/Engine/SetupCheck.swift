import Foundation

/// The "Setup check" at the top of Settings: one line per thing a lock-in depends on, so a missing permission
/// or key is visible before it silently weakens a session. Pure; SettingsView supplies the inputs.
struct SetupCheck: Equatable {
    enum State: Equatable {
        case ready
        /// Works, with a limitation the user may accept (Discord off, Google not connected).
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
        /// Only screen memory still depends on it; the key itself is no longer a row (users don't set one).
        var openAIKey: TokenSource
        var discordEnabled: Bool
        var discordToken: TokenSource
        var googleConnected: Bool
        var screenMemoryEnabled: Bool = false
        var screenRecording: Bool = false
        /// The Google services that are on and granted, in display order.
        var googleServices: [GoogleService] = []
        /// Services that are on but missing from the token's scopes (connected before Gmail was added, say).
        var googleNotGranted: [GoogleService] = []
        /// Both Tofu Do Not Disturb shortcuts are in the Shortcuts library.
        var doNotDisturbShortcuts: Bool = false
    }

    static func items(_ inputs: Inputs) -> [Item] {
        [
            Item(title: "Accessibility",
                 state: inputs.accessibility ? .ready : .needsAction,
                 detail: inputs.accessibility ? "Windows can be placed"
                    : "Needed to place app and Arc windows — see Window placement below"),
            chromeItem(inputs.chrome),
            discordItem(enabled: inputs.discordEnabled, token: inputs.discordToken),
            screenMemoryItem(enabled: inputs.screenMemoryEnabled, permission: inputs.screenRecording,
                             hasKey: inputs.openAIKey != .none),
            googleItem(inputs),
            Item(title: "Do Not Disturb",
                 state: inputs.doNotDisturbShortcuts ? .ready : .optional,
                 detail: inputs.doNotDisturbShortcuts ? "Turns on for each work block"
                    : "Off — add its shortcuts in Do Not Disturb below"),
        ]
    }

    /// "Calendar, Tasks and Gmail", "Calendar and Gmail", "Gmail".
    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    private static func googleItem(_ inputs: Inputs) -> Item {
        let manage = " · Manage in Connections"
        guard inputs.googleConnected else {
            return Item(title: "Google", state: .optional, detail: "Not connected (optional)" + manage)
        }
        if !inputs.googleNotGranted.isEmpty {
            return Item(title: "Google", state: .optional,
                        detail: "Reconnect to enable " + list(inputs.googleNotGranted.map(\.shortTitle)) + manage)
        }
        let names = inputs.googleServices.map(\.shortTitle)
        return Item(title: "Google", state: .ready,
                    detail: (names.isEmpty ? "Connected, every service is off" : list(names) + " on") + manage)
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

    private static func screenMemoryItem(enabled: Bool, permission: Bool, hasKey: Bool) -> Item {
        guard enabled else { return Item(title: "Screen memory", state: .optional, detail: "Off") }
        if !permission {
            return Item(title: "Screen memory", state: .needsAction,
                        detail: "Allow Screen Recording for Tofu — see Screen memory below")
        }
        if !hasKey {
            return Item(title: "Screen memory", state: .needsAction, detail: "Needs an OpenAI key to describe screenshots")
        }
        return Item(title: "Screen memory", state: .ready, detail: "A screenshot every 5 minutes is described and remembered")
    }

    private static func discordItem(enabled: Bool, token: TokenSource) -> Item {
        guard enabled else { return Item(title: "Discord", state: .optional, detail: "Announcements are off") }
        if token == .none {
            return Item(title: "Discord", state: .needsAction, detail: "Announcements are on but there is no bot token")
        }
        return Item(title: "Discord", state: .ready, detail: token.label)
    }
}
