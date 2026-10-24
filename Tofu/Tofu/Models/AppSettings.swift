import Foundation

/// User preferences persisted in store.json. The Discord bot token is NOT here (Keychain only).
struct AppSettings: Codable, Equatable {
    var displayName: String
    var discordEnabled: Bool
    var giveUpTemplate: String
    var channelCache: [String: String]   // guildID -> channelID that last succeeded
    /// Ask to wrap up the day automatically at `dayEndMinutes`.
    var dayEndPromptEnabled: Bool
    /// End of the day in minutes after midnight (22:00 = 1320).
    var dayEndMinutes: Int
    /// `DayKey` of the last automatic wrap-up prompt, so it is shown once per day.
    var lastDayPromptKey: String?
    /// Show the "Good morning" screen the first time the Mac is used each day.
    var morningScreenEnabled: Bool
    /// `DayKey` of the last day the morning screen was shown, so it shows once per day.
    var lastMorningKey: String?
    /// Show the study companion overlay while locked in.
    var companionEnabled: Bool
    /// How the companion talks.
    var companionPersonality: CompanionPersonality
    /// Mirror the day's priorities into Google Tasks.
    var googleTasksSyncEnabled: Bool
    /// Write finished sessions to Google Calendar.
    var googleSessionLogEnabled: Bool
    /// Show Google Calendar events in the day view.
    var googleShowEventsEnabled: Bool
    /// The Google calendar sessions are written to, once chosen or created.
    var googleCalendarID: String?
    /// Every 5 minutes while locked in, describe a screenshot with OpenAI and remember the description.
    var screenMemoryEnabled: Bool

    init(displayName: String = NSFullUserName(), discordEnabled: Bool = false,
         giveUpTemplate: String = "I give up on {subject}", channelCache: [String: String] = [:],
         dayEndPromptEnabled: Bool = true, dayEndMinutes: Int = 22 * 60, lastDayPromptKey: String? = nil,
         morningScreenEnabled: Bool = true, lastMorningKey: String? = nil,
         companionEnabled: Bool = true, companionPersonality: CompanionPersonality = .gentle,
         googleTasksSyncEnabled: Bool = true, googleSessionLogEnabled: Bool = true,
         googleShowEventsEnabled: Bool = true, googleCalendarID: String? = nil,
         screenMemoryEnabled: Bool = true) {
        self.displayName = displayName
        self.discordEnabled = discordEnabled
        self.giveUpTemplate = giveUpTemplate
        self.channelCache = channelCache
        self.dayEndPromptEnabled = dayEndPromptEnabled
        self.dayEndMinutes = dayEndMinutes
        self.lastDayPromptKey = lastDayPromptKey
        self.morningScreenEnabled = morningScreenEnabled
        self.lastMorningKey = lastMorningKey
        self.companionEnabled = companionEnabled
        self.companionPersonality = companionPersonality
        self.googleTasksSyncEnabled = googleTasksSyncEnabled
        self.googleSessionLogEnabled = googleSessionLogEnabled
        self.googleShowEventsEnabled = googleShowEventsEnabled
        self.googleCalendarID = googleCalendarID
        self.screenMemoryEnabled = screenMemoryEnabled
    }
}

extension AppSettings {
    /// Fields added later fall back to their defaults, so older store files still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        self.init(
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName) ?? defaults.displayName,
            discordEnabled: try container.decodeIfPresent(Bool.self, forKey: .discordEnabled) ?? defaults.discordEnabled,
            giveUpTemplate: try container.decodeIfPresent(String.self, forKey: .giveUpTemplate) ?? defaults.giveUpTemplate,
            channelCache: try container.decodeIfPresent([String: String].self, forKey: .channelCache) ?? [:],
            dayEndPromptEnabled: try container.decodeIfPresent(Bool.self, forKey: .dayEndPromptEnabled)
                ?? defaults.dayEndPromptEnabled,
            dayEndMinutes: try container.decodeIfPresent(Int.self, forKey: .dayEndMinutes) ?? defaults.dayEndMinutes,
            lastDayPromptKey: try container.decodeIfPresent(String.self, forKey: .lastDayPromptKey),
            morningScreenEnabled: try container.decodeIfPresent(Bool.self, forKey: .morningScreenEnabled)
                ?? defaults.morningScreenEnabled,
            lastMorningKey: try container.decodeIfPresent(String.self, forKey: .lastMorningKey),
            companionEnabled: try container.decodeIfPresent(Bool.self, forKey: .companionEnabled)
                ?? defaults.companionEnabled,
            companionPersonality: try container.decodeIfPresent(CompanionPersonality.self, forKey: .companionPersonality)
                ?? defaults.companionPersonality,
            googleTasksSyncEnabled: try container.decodeIfPresent(Bool.self, forKey: .googleTasksSyncEnabled)
                ?? defaults.googleTasksSyncEnabled,
            googleSessionLogEnabled: try container.decodeIfPresent(Bool.self, forKey: .googleSessionLogEnabled)
                ?? defaults.googleSessionLogEnabled,
            googleShowEventsEnabled: try container.decodeIfPresent(Bool.self, forKey: .googleShowEventsEnabled)
                ?? defaults.googleShowEventsEnabled,
            googleCalendarID: try container.decodeIfPresent(String.self, forKey: .googleCalendarID),
            screenMemoryEnabled: try container.decodeIfPresent(Bool.self, forKey: .screenMemoryEnabled)
                ?? defaults.screenMemoryEnabled)
    }
}

/// Everything stored in store.json.
struct StoreData: Codable, Equatable {
    var version: Int = 1
    var subjects: [Subject] = []
    var sessions: [Session] = []
    var settings: AppSettings = AppSettings()
    var dayPlans: [DayPlan] = []

    static var empty: StoreData { StoreData() }
}

extension StoreData {
    /// `dayPlans` (added later) may be missing from older store files.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
                  subjects: try container.decode([Subject].self, forKey: .subjects),
                  sessions: try container.decode([Session].self, forKey: .sessions),
                  settings: try container.decode(AppSettings.self, forKey: .settings),
                  dayPlans: try container.decodeIfPresent([DayPlan].self, forKey: .dayPlans) ?? [])
    }
}
