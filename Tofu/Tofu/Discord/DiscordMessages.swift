import Foundation

/// Exact Discord message texts (spec §9). Durations always go through `TimeFormat.short`.
enum DiscordMessages {
    /// "🔒 **{name}** is locked in on **{subject}**" + " [{tierName}]" + " (goal {TimeFormat.short(goal)})" in goal mode.
    static func start(name: String, subject: String, mode: SessionMode, tierName: String? = nil) -> String {
        let tierSuffix = (tierName?.isEmpty == false) ? " [\(tierName!)]" : ""
        let base = "🔒 **\(name)** is locked in on **\(subject)**\(tierSuffix)"
        guard let goal = mode.goalSeconds else { return base }
        return base + " (goal \(TimeFormat.short(goal)))"
    }

    /// "✅ **{name}** locked in on **{subject}** [{tierName}] for **{dur}** · tried other apps **{attempts}×** · closed **{tabs}** tabs"
    /// When streakDays > 1, appends streak badge to encourage consistency.
    static func completed(name: String, subject: String, duration: TimeInterval, attempts: Int, tabs: Int, streakDays: Int = 0, tierName: String? = nil) -> String {
        let tierSuffix = (tierName?.isEmpty == false) ? " [\(tierName!)]" : ""
        var msg = "✅ **\(name)** locked in on **\(subject)**\(tierSuffix) for **\(TimeFormat.short(duration))**"
            + " · tried other apps **\(attempts)×** · closed **\(tabs)** tabs"
        if streakDays > 1 {
            msg += " · 🔥 \(streakDays)d streak"
        }
        return msg
    }

    /// One priority just got finished. An update, not the end-of-day overview.
    /// "Update: **{name}** finished **{title}**" and, when it belongs to a setup, " · **{setup}**".
    static func priorityUpdate(name: String, title: String, setup: String?) -> String {
        let line = "Update: **\(name)** finished **\(title)**"
        guard let setup = setup?.trimmingCharacters(in: .whitespacesAndNewlines), !setup.isEmpty else { return line }
        return line + " · **\(setup)**"
    }

    /// "🏳️ **{name}** bailed on **{subject}** after **{dur}** (goal {goal}) · tried other apps **{attempts}×**"
    /// The flag is written as escapes (U+1F3F3 U+FE0F) so the variation selector cannot be lost in copy/paste.
    /// Optional reason adds accountability context when provided.
    static func bailed(name: String, subject: String, duration: TimeInterval, goalMinutes: Int, attempts: Int, reason: String? = nil) -> String {
        let goal = TimeFormat.short(TimeInterval(goalMinutes) * 60)
        var msg = "\u{1F3F3}\u{FE0F} **\(name)** bailed on **\(subject)** after **\(TimeFormat.short(duration))**"
            + " (goal \(goal)) · tried other apps **\(attempts)×**"
        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            msg += " · Reason: \(reason)"
        }
        return msg
    }

    /// Rich Discord embed for focus session completion or bail notification.
    static func sessionEmbed(subject: String, isCompleted: Bool, duration: TimeInterval,
                             attempts: Int, tabs: Int, streakDays: Int = 0, tierName: String? = nil) -> DiscordEmbed {
        let color = isCompleted ? 0x059669 : 0xE11D48
        let title = isCompleted ? "✅ Focus Block Completed" : "🏳️ Focus Block Bailed"
        var fields: [DiscordEmbed.Field] = [
            .init(name: "Subject", value: subject, inline: true),
            .init(name: "Duration", value: TimeFormat.short(duration), inline: true),
            .init(name: "Distraction Attempts", value: "\(attempts)", inline: true),
            .init(name: "Tabs Closed", value: "\(tabs)", inline: true)
        ]
        if let tier = tierName, !tier.isEmpty {
            fields.append(.init(name: "Tier", value: tier, inline: true))
        }
        if streakDays > 1 {
            fields.append(.init(name: "Streak", value: "🔥 \(streakDays) days", inline: true))
        }
        return DiscordEmbed(title: title, description: "Accountability check-in from Tofu", color: color, fields: fields)
    }
}
