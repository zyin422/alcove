import Foundation

/// User preferences persisted in store.json. The Discord bot token is NOT here (Keychain only).
struct AppSettings: Codable, Equatable {
    var displayName: String
    var discordEnabled: Bool
    var giveUpTemplate: String
    var channelCache: [String: String]   // guildID -> channelID that last succeeded

    init(displayName: String = NSFullUserName(), discordEnabled: Bool = false,
         giveUpTemplate: String = "I give up on {subject}", channelCache: [String: String] = [:]) {
        self.displayName = displayName
        self.discordEnabled = discordEnabled
        self.giveUpTemplate = giveUpTemplate
        self.channelCache = channelCache
    }
}

/// Everything stored in store.json.
struct StoreData: Codable, Equatable {
    var version: Int = 1
    var subjects: [Subject] = []
    var sessions: [Session] = []
    var settings: AppSettings = AppSettings()

    static var empty: StoreData { StoreData() }
}
