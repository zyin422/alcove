import Foundation

/// Live `Announcing`: posts session messages to every Discord server the bot is in (spec §9).
/// Fire-and-forget: `announce` returns at once and never throws; failures end up as one toast.
@MainActor final class DiscordAnnouncer: Announcing {
    static let failureMessage = "Discord: couldn't post (check bot token/permissions)"

    private let token: () -> String?
    private let settings: () -> AppSettings
    private let onCacheUpdate: ([String: String]) -> Void
    private let toaster: Toasting
    private let makeClient: (String) -> DiscordClient

    init(token: @escaping () -> String?, settings: @escaping () -> AppSettings,
         onCacheUpdate: @escaping ([String: String]) -> Void, toaster: Toasting,
         makeClient: @escaping (String) -> DiscordClient = { DiscordClient(token: $0) }) {
        self.token = token
        self.settings = settings
        self.onCacheUpdate = onCacheUpdate
        self.toaster = toaster
        self.makeClient = makeClient
    }

    /// Does nothing when Discord is disabled or there is no token. Otherwise broadcasts in a Task:
    /// channels that accepted the message are merged into the channel cache; if nothing was posted,
    /// one toast is shown.
    func announce(_ content: String) {
        let current = settings()
        guard current.discordEnabled else { return }
        let botToken = (token() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !botToken.isEmpty else { return }
        let client = makeClient(botToken)
        let cache = current.channelCache
        Task {
            let report = await client.broadcast(content, channelCache: cache)
            self.handle(report)
        }
    }

    private func handle(_ report: DiscordPostReport) {
        guard !report.posted.isEmpty else {
            toaster.show(Self.failureMessage)
            return
        }
        var merged = settings().channelCache
        for (guildID, channelID) in report.posted {
            merged[guildID] = channelID
        }
        onCacheUpdate(merged)
    }
}
