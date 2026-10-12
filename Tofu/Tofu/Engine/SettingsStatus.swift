import Foundation

/// Pure texts and helpers for the Settings screen (status lines, invite link, previews).
enum SettingsStatus {
    /// Shown by "Test connection" when no bot token is saved.
    static let noToken = "Save a bot token first"
    /// Shown while "Test connection" runs.
    static let testing = "Testing…"
    /// Shown in the Chrome section before "Request access" has been clicked.
    static let chromeUnchecked = "Not checked yet"
    /// Shown while the Automation request (and possibly the macOS prompt) is pending.
    static let chromeWaiting = "Waiting for macOS…"
    /// Spec §9 invite link; `<APP_ID>` is the Discord application id. 3072 = View Channel + Send Messages.
    static let inviteTemplate = "https://discord.com/oauth2/authorize?client_id=<APP_ID>&scope=bot&permissions=3072"

    /// Status line for Settings › Discord › Test connection.
    /// Success: "Connected as lockbot · 3 servers". Failure: "Failed: HTTP 401 — the bot token is invalid".
    static func discordResult(_ result: Result<(user: DiscordUser, guildCount: Int), Error>) -> String {
        switch result {
        case .success(let value):
            let servers = value.guildCount == 1 ? "1 server" : "\(value.guildCount) servers"
            let text = "Connected as \(value.user.username) · \(servers)"
            return value.guildCount == 0 ? text + " — invite the bot to a server" : text
        case .failure(let error):
            return "Failed: " + describe(error)
        }
    }

    /// Status line for Settings › Chrome › Request access. nil means the script ran, so control is allowed.
    static func chromeResult(_ error: ChromeError?) -> String {
        guard let error else { return "Chrome control allowed" }
        switch error {
        case .notInstalled:
            return "Google Chrome not installed"
        case .automationDenied:
            return "Denied — enable in System Settings › Privacy & Security › Automation"
        case .profileNotReady:
            return "Chrome is still starting — try again in a moment"
        case .scriptFailed(let message):
            return "Chrome script failed: \(message)"
        }
    }

    /// The bot invite URL for a Discord application id, or nil unless the trimmed id is non-empty ASCII digits.
    static func inviteURL(appID: String) -> URL? {
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: inviteTemplate.replacingOccurrences(of: "<APP_ID>", with: id))
    }

    /// The give-up phrase as it will appear for `subject` (same substitution as SessionEngine.giveUpPhrase).
    static func phrasePreview(template: String, subject: String = "CS128") -> String {
        template.replacingOccurrences(of: "{subject}", with: subject)
    }

    /// "No demo data loaded", "1 demo session loaded", "43 demo sessions loaded".
    static func demoSummary(count: Int) -> String {
        switch count {
        case ...0: return "No demo data loaded"
        case 1: return "1 demo session loaded"
        default: return "\(count) demo sessions loaded"
        }
    }

    /// Token as typed/pasted: trims whitespace and a leading "Bot " prefix. nil when nothing is left.
    static func cleanedToken(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bot ") {
            token = String(token.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token.isEmpty ? nil : token
    }

    private static func describe(_ error: Error) -> String {
        guard let discordError = error as? DiscordError else { return error.localizedDescription }
        switch discordError {
        case .http(401):
            return "HTTP 401 — the bot token is invalid"
        case .http(let code):
            return "HTTP \(code)"
        case .transport(let message):
            return "network error (\(message))"
        case .decoding:
            return "unexpected response from Discord"
        }
    }
}
