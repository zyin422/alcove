import Foundation

/// Exact Discord message texts (spec §9). Durations always go through `TimeFormat.short`.
enum DiscordMessages {
    /// "🔒 **{name}** is locked in on **{subject}**" + " (goal {TimeFormat.short(goal)})" in goal mode.
    static func start(name: String, subject: String, mode: SessionMode) -> String {
        let base = "🔒 **\(name)** is locked in on **\(subject)**"
        guard let goal = mode.goalSeconds else { return base }
        return base + " (goal \(TimeFormat.short(goal)))"
    }

    /// "✅ **{name}** locked in on **{subject}** for **{dur}** · tried other apps **{attempts}×** · closed **{tabs}** tabs"
    static func completed(name: String, subject: String, duration: TimeInterval, attempts: Int, tabs: Int) -> String {
        "✅ **\(name)** locked in on **\(subject)** for **\(TimeFormat.short(duration))**"
            + " · tried other apps **\(attempts)×** · closed **\(tabs)** tabs"
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
    static func bailed(name: String, subject: String, duration: TimeInterval, goalMinutes: Int, attempts: Int) -> String {
        let goal = TimeFormat.short(TimeInterval(goalMinutes) * 60)
        return "\u{1F3F3}\u{FE0F} **\(name)** bailed on **\(subject)** after **\(TimeFormat.short(duration))**"
            + " (goal \(goal)) · tried other apps **\(attempts)×**"
    }
}
