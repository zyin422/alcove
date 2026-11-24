import AppKit
import Foundation

/// Discrete acoustic cues for tactile feedback during session and break transitions.
enum SoundCue: String, CaseIterable {
    case sessionStart
    case sessionCompleted
    case breakStart
    case breakEnd
    case distractionIntercepted

    var soundName: String {
        switch self {
        case .sessionStart: return "Pop"
        case .sessionCompleted: return "Hero"
        case .breakStart: return "Glass"
        case .breakEnd: return "Ping"
        case .distractionIntercepted: return "Basso"
        }
    }

    @MainActor
    func play(enabled: Bool = true) {
        guard enabled else { return }
        NSSound(named: soundName)?.play()
    }
}

/// Ambient soundscape to mask background distractions during lock-in sessions.
enum FocusSound: String, Codable, CaseIterable, Identifiable {
    case off = "Off"
    case rain = "Gentle Rain"
    case stream = "Forest Stream"
    case lofiDrone = "Analog Lofi Pad"
    case gammaBinaural = "Gamma Focus (40Hz)"
    case alphaBinaural = "Alpha Waves (10Hz)"
    case thetaBinaural = "Theta Calm (6Hz)"
    case brownNoise = "Deep Brown Noise"
    case pinkNoise = "Warm Pink Noise"
    case whiteNoise = "White Noise"

    var id: String { rawValue }
}

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
    /// Show the "Good morning" screen until a work block starts that day.
    var morningScreenEnabled: Bool
    /// `DayKey` of the last day a work block started, so later wakes that day stay quiet.
    var lastMorningKey: String?
    /// When the morning screen comes back after "Start in 10 minutes". Set means that delay was used.
    var morningPostponeUntil: Date?
    /// `DayKey` when "Not now" (10-minute delay) was used, capping it to once per day.
    var lastPostponeKey: String?
    /// When the quiet time after a real block ends.
    var morningGraceUntil: Date?
    /// Seconds of grace frozen while the lid is closed. Set means the deadline is not running.
    var morningGraceHeld: TimeInterval?
    /// The block `morningGraceUntil` belongs to.
    var morningGraceSessionID: UUID?
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
    /// When true, a break stops app blocking and the tab check. Off by default, so Discord and
    /// other off-task pages stay closed and the break only pauses the timer.
    var allowOffTaskDuringBreak: Bool
    /// Full-screen lock on the Mac between 00:00 and 04:00 AM unless 15m planning mode is running.
    var bedtimeGuardEnabled: Bool
    /// The AI digest or RSS feed URL opened in Planning Mode.
    var aiFeedURL: String
    /// DayKey when midnight 15m planning mode was last activated, capping it to once per night.
    var lastMidnightPlanningKey: String?
    /// DayKey when daytime 15m planning mode was last activated, capping it to once per day.
    var lastDayPlanningKey: String?
    /// Ambient focus audio played during lock-in sessions.
    var focusSound: FocusSound
    /// Volume of ambient focus audio (0.0 to 1.0).
    var focusSoundVolume: Double
    /// Launch Tofu automatically when logging into macOS.
    var autoLaunchAtLogin: Bool
    /// Keep Tofu running continuously during daytime hours (07:30–23:00) to prevent avoidance.
    var dayGuardianEnabled: Bool
    /// Chosen Kokoro neural voice persona.
    var kokoroVoice: KokoroVoice
    /// Volume of voice coaching announcements (0.0 to 1.0).
    var voiceVolume: Double
    /// Target focused minutes per day (e.g. 240 for 4 hours).
    var dailyTargetMinutes: Int
    /// Discrete acoustic cues on block start, finish, breaks, and distraction intercepts.
    var soundCuesEnabled: Bool

    init(displayName: String = NSFullUserName(), discordEnabled: Bool = false,
         giveUpTemplate: String = "I give up on {subject}", channelCache: [String: String] = [:],
         dayEndPromptEnabled: Bool = true, dayEndMinutes: Int = 22 * 60, lastDayPromptKey: String? = nil,
         morningScreenEnabled: Bool = true, lastMorningKey: String? = nil, morningPostponeUntil: Date? = nil,
         lastPostponeKey: String? = nil,
         morningGraceUntil: Date? = nil, morningGraceHeld: TimeInterval? = nil, morningGraceSessionID: UUID? = nil,
         companionEnabled: Bool = false, companionPersonality: CompanionPersonality = .escalation,
         googleTasksSyncEnabled: Bool = true, googleSessionLogEnabled: Bool = true,
         googleShowEventsEnabled: Bool = true, googleCalendarID: String? = nil,
         allowOffTaskDuringBreak: Bool = false,
         bedtimeGuardEnabled: Bool = true,
         aiFeedURL: String = "https://news.ycombinator.com",
         lastMidnightPlanningKey: String? = nil,
         lastDayPlanningKey: String? = nil,
         focusSound: FocusSound = .off,
         focusSoundVolume: Double = 0.5,
         autoLaunchAtLogin: Bool = true,
         dayGuardianEnabled: Bool = true,
         kokoroVoice: KokoroVoice = .heart,
         voiceVolume: Double = 1.0,
         dailyTargetMinutes: Int = 4 * 60,
         soundCuesEnabled: Bool = true) {
        self.displayName = displayName
        self.discordEnabled = discordEnabled
        self.giveUpTemplate = giveUpTemplate
        self.channelCache = channelCache
        self.dayEndPromptEnabled = dayEndPromptEnabled
        self.dayEndMinutes = dayEndMinutes
        self.lastDayPromptKey = lastDayPromptKey
        self.morningScreenEnabled = morningScreenEnabled
        self.lastMorningKey = lastMorningKey
        self.morningPostponeUntil = morningPostponeUntil
        self.lastPostponeKey = lastPostponeKey
        self.morningGraceUntil = morningGraceUntil
        self.morningGraceHeld = morningGraceHeld
        self.morningGraceSessionID = morningGraceSessionID
        self.companionEnabled = companionEnabled
        self.companionPersonality = companionPersonality
        self.googleTasksSyncEnabled = googleTasksSyncEnabled
        self.googleSessionLogEnabled = googleSessionLogEnabled
        self.googleShowEventsEnabled = googleShowEventsEnabled
        self.googleCalendarID = googleCalendarID
        self.allowOffTaskDuringBreak = allowOffTaskDuringBreak
        self.bedtimeGuardEnabled = bedtimeGuardEnabled
        self.aiFeedURL = aiFeedURL
        self.lastMidnightPlanningKey = lastMidnightPlanningKey
        self.lastDayPlanningKey = lastDayPlanningKey
        self.focusSound = focusSound
        self.focusSoundVolume = focusSoundVolume
        self.autoLaunchAtLogin = autoLaunchAtLogin
        self.dayGuardianEnabled = dayGuardianEnabled
        self.kokoroVoice = kokoroVoice
        self.voiceVolume = voiceVolume
        self.dailyTargetMinutes = dailyTargetMinutes
        self.soundCuesEnabled = soundCuesEnabled
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
            morningPostponeUntil: try container.decodeIfPresent(Date.self, forKey: .morningPostponeUntil),
            lastPostponeKey: try container.decodeIfPresent(String.self, forKey: .lastPostponeKey),
            morningGraceUntil: try container.decodeIfPresent(Date.self, forKey: .morningGraceUntil),
            morningGraceHeld: try container.decodeIfPresent(TimeInterval.self, forKey: .morningGraceHeld),
            morningGraceSessionID: try container.decodeIfPresent(UUID.self, forKey: .morningGraceSessionID),
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
            allowOffTaskDuringBreak: try container.decodeIfPresent(Bool.self, forKey: .allowOffTaskDuringBreak)
                ?? defaults.allowOffTaskDuringBreak,
            bedtimeGuardEnabled: try container.decodeIfPresent(Bool.self, forKey: .bedtimeGuardEnabled)
                ?? defaults.bedtimeGuardEnabled,
            aiFeedURL: try container.decodeIfPresent(String.self, forKey: .aiFeedURL)
                ?? defaults.aiFeedURL,
            lastMidnightPlanningKey: try container.decodeIfPresent(String.self, forKey: .lastMidnightPlanningKey),
            lastDayPlanningKey: try container.decodeIfPresent(String.self, forKey: .lastDayPlanningKey),
            focusSound: try container.decodeIfPresent(FocusSound.self, forKey: .focusSound)
                ?? defaults.focusSound,
            focusSoundVolume: try container.decodeIfPresent(Double.self, forKey: .focusSoundVolume)
                ?? defaults.focusSoundVolume,
            autoLaunchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .autoLaunchAtLogin)
                ?? defaults.autoLaunchAtLogin,
            dayGuardianEnabled: try container.decodeIfPresent(Bool.self, forKey: .dayGuardianEnabled)
                ?? defaults.dayGuardianEnabled,
            kokoroVoice: try container.decodeIfPresent(KokoroVoice.self, forKey: .kokoroVoice)
                ?? defaults.kokoroVoice,
            voiceVolume: try container.decodeIfPresent(Double.self, forKey: .voiceVolume)
                ?? defaults.voiceVolume,
            dailyTargetMinutes: try container.decodeIfPresent(Int.self, forKey: .dailyTargetMinutes)
                ?? defaults.dailyTargetMinutes,
            soundCuesEnabled: try container.decodeIfPresent(Bool.self, forKey: .soundCuesEnabled)
                ?? defaults.soundCuesEnabled)
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
