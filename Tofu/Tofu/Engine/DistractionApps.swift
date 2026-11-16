import Foundation

/// Native apps that are blocked from being unblocked by the assistant during focus sessions:
/// social media, messaging, gaming, streaming, and entertainment.
/// Unlike general productivity tools (e.g. Calculator, Xcode), these cannot be allowed mid-session via chat.
enum DistractionApps {
    enum Category: String, CaseIterable {
        case messaging = "messaging"
        case social = "social media"
        case gaming = "gaming"
        case streaming = "streaming & video"
        case entertainment = "entertainment"
        case browsers = "unmonitored browsers"
    }

    static let apps: [Category: [String]] = [
        .messaging: [
            "com.hnc.Discord",
            "ru.keepcoder.Telegram",
            "com.tdesktop.Telegram",
            "com.tinyspeck.slackmacgap",
            "net.whatsapp.WhatsApp",
            "com.whatsapp",
            "com.apple.MobileSMS",
            "org.whispersystems.signal-desktop",
            "com.tencent.xinWeChat",
            "com.facebook.archon.developerID",
            "com.skype.skype",
        ],
        .social: [
            "com.atebits.Tweetie2",
            "com.twitter.twitter-mac",
            "com.reddit.Reddit",
            "com.zhiliaoapp.musically",
            "com.bilibili.bilibili",
            "tv.danmaku.bili",
        ],
        .gaming: [
            "com.valvesoftware.steam",
            "com.epicgames.EpicGamesLauncher",
            "net.battle.app",
            "com.riotgames.LeagueofLegends.LeagueClientUx",
            "com.mojang.minecraftlauncher",
            "com.Roblox.RobloxPlayer",
            "com.ea.mac.origin",
            "com.gog.galaxy",
            "com.apple.Chess",
            "com.supercell.clashroyale",
        ],
        .streaming: [
            "com.netflix.Netflix",
            "com.apple.TV",
            "tv.plex.desktop",
        ],
        .entertainment: [
            "com.apple.GameCenter",
            "com.apple.News",
            "com.apple.stocks",
            "com.apple.FaceTime",
        ],
        .browsers: [
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.operasoftware.Opera",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.torproject.torbrowser",
        ],
    ]

    /// Set of all prohibited bundle identifiers.
    static var allBundleIDs: Set<String> {
        Set(apps.values.flatMap { $0 })
    }

    /// Finds the category for this bundle ID or app name, or nil if not a prohibited distraction.
    static func category(of bundleID: String) -> Category? {
        let lower = bundleID.lowercased()
        guard !lower.isEmpty else { return nil }
        for (category, ids) in apps {
            if ids.contains(where: { id in
                let target = id.lowercased()
                return lower == target || lower.hasPrefix(target + ".") || lower.contains(target)
            }) {
                return category
            }
        }
        return nil
    }

    /// True when the bundle ID corresponds to a prohibited distraction app.
    static func isDistraction(_ bundleID: String) -> Bool {
        category(of: bundleID) != nil
    }
}
