import Foundation

/// Sites that are closed during a lock-in without asking the AI: social media, email and messaging,
/// streaming, YouTube and shopping. A subject's study sites and hosts the user explicitly allowed still win.
/// Matching covers subdomains (`m.youtube.com`), except for hosts under `exceptions`.
enum DistractionList {
    enum Category: String, CaseIterable {
        case social = "social media"
        case messaging = "email and messaging"
        case streaming = "streaming"
        case video = "YouTube"
        case shopping = "shopping"
    }

    static let domains: [Category: [String]] = [
        .social: ["facebook.com", "instagram.com", "tiktok.com", "x.com", "twitter.com", "reddit.com",
                  "snapchat.com", "pinterest.com", "tumblr.com", "threads.net", "threads.com", "bsky.app",
                  "linkedin.com", "9gag.com", "imgur.com"],
        .messaging: ["mail.google.com", "gmail.com", "inbox.google.com", "chat.google.com",
                     "outlook.live.com", "outlook.office.com", "outlook.office365.com", "outlook.com",
                     "mail.yahoo.com", "mail.proton.me", "mail.aol.com", "web.whatsapp.com", "whatsapp.com",
                     "messenger.com", "web.telegram.org", "discord.com", "groupme.com"],
        .streaming: ["netflix.com", "twitch.tv", "kick.com", "hulu.com", "disneyplus.com", "max.com", "hbomax.com",
                     "primevideo.com", "peacocktv.com", "paramountplus.com", "crunchyroll.com"],
        .video: ["youtube.com", "youtu.be"],
        .shopping: ["amazon.com", "ebay.com", "etsy.com", "shein.com", "temu.com", "aliexpress.com",
                    "walmart.com", "target.com", "bestbuy.com"],
    ]

    /// Work tools that live under a blocked domain (AWS docs and console are under amazon.com).
    static let exceptions = ["aws.amazon.com", "developer.amazon.com"]

    /// Every blocked domain, for `TabTriage`.
    static var hosts: [String] {
        Category.allCases.flatMap { domains[$0] ?? [] }
    }

    /// The category `host` falls under, nil when it is not a known distraction.
    static func category(of host: String) -> Category? {
        let host = DomainMatcher.normalize(host)
        guard !host.isEmpty, !matches(host, any: exceptions) else { return nil }
        return Category.allCases.first { matches(host, any: domains[$0] ?? []) }
    }

    /// `host` equals one of `domains` or is a subdomain of one.
    static func matches(_ host: String, any domains: [String]) -> Bool {
        domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
