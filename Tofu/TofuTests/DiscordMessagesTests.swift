import XCTest
@testable import Tofu

final class DiscordMessagesTests: XCTestCase {
    func testStartOpenMode() {
        XCTAssertEqual(DiscordMessages.start(name: "Alex", subject: "CS128", mode: .open),
                       "🔒 **Alex** is locked in on **CS128**")
    }

    func testStartGoalModeAppendsGoalInMinutes() {
        XCTAssertEqual(DiscordMessages.start(name: "Alex", subject: "CS128", mode: .goal(minutes: 50)),
                       "🔒 **Alex** is locked in on **CS128** (goal 50m)")
    }

    func testStartGoalModeOverAnHour() {
        let text = DiscordMessages.start(name: "Alex", subject: "MATH241", mode: .goal(minutes: 90))
        XCTAssertEqual(text, "🔒 **Alex** is locked in on **MATH241** (goal 1h 30m)")
        XCTAssertTrue(text.hasSuffix("(goal 1h 30m)"))
    }

    func testCompleted() {
        let text = DiscordMessages.completed(name: "Alex", subject: "CS128", duration: 4800 + 59,
                                             attempts: 3, tabs: 2)
        XCTAssertEqual(text,
                       "✅ **Alex** locked in on **CS128** for **1h 20m** · tried other apps **3×** · closed **2** tabs")
    }

    func testCompletedZeroDuration() {
        let text = DiscordMessages.completed(name: "Alex", subject: "CS128", duration: 30, attempts: 0, tabs: 0)
        XCTAssertEqual(text,
                       "✅ **Alex** locked in on **CS128** for **0m** · tried other apps **0×** · closed **0** tabs")
    }

    func testPriorityUpdateStandsApartFromTheDayRecap() {
        XCTAssertEqual(DiscordMessages.priorityUpdate(name: "Zixuan", title: "Math241 review", setup: nil),
                       "Update: **Zixuan** finished **Math241 review**")
        XCTAssertEqual(DiscordMessages.priorityUpdate(name: "Zixuan", title: "Math241 review", setup: "MATH241"),
                       "Update: **Zixuan** finished **Math241 review** · **MATH241**")
        XCTAssertEqual(DiscordMessages.priorityUpdate(name: "Zixuan", title: "Read", setup: "  "),
                       "Update: **Zixuan** finished **Read**")
    }

    func testBailed() {
        let text = DiscordMessages.bailed(name: "Alex", subject: "CS128", duration: 12 * 60 + 40,
                                          goalMinutes: 50, attempts: 4)
        XCTAssertEqual(text,
                       "🏳️ **Alex** bailed on **CS128** after **12m** (goal 50m) · tried other apps **4×**")
        // The white flag must keep its emoji variation selector.
        XCTAssertTrue(text.unicodeScalars.starts(with: "\u{1F3F3}\u{FE0F} ".unicodeScalars))
    }

    func testBailedLongGoal() {
        let text = DiscordMessages.bailed(name: "Sam", subject: "MATH241", duration: 3600 + 60,
                                          goalMinutes: 90, attempts: 1)
        XCTAssertEqual(text,
                       "🏳️ **Sam** bailed on **MATH241** after **1h 1m** (goal 1h 30m) · tried other apps **1×**")
    }

    func testCompletedWithStreakBadge() {
        let text = DiscordMessages.completed(name: "Zixuan", subject: "Tofu", duration: 3600,
                                             attempts: 0, tabs: 0, streakDays: 5)
        XCTAssertEqual(text,
                       "✅ **Zixuan** locked in on **Tofu** for **1h 0m** · tried other apps **0×** · closed **0** tabs · 🔥 5d streak")

        let noStreak = DiscordMessages.completed(name: "Zixuan", subject: "Tofu", duration: 3600,
                                                attempts: 0, tabs: 0, streakDays: 1)
        XCTAssertEqual(noStreak,
                       "✅ **Zixuan** locked in on **Tofu** for **1h 0m** · tried other apps **0×** · closed **0** tabs")
    }

    func testBailedWithAccountabilityReason() {
        let text = DiscordMessages.bailed(name: "Alex", subject: "CS128", duration: 600,
                                          goalMinutes: 45, attempts: 2, reason: "Urgent phone call")
        XCTAssertEqual(text,
                       "🏳️ **Alex** bailed on **CS128** after **10m** (goal 45m) · tried other apps **2×** · Reason: Urgent phone call")
    }

    func testSessionEmbedGeneration() {
        let completedEmbed = DiscordMessages.sessionEmbed(subject: "Research", isCompleted: true,
                                                          duration: 3600, attempts: 1, tabs: 2, streakDays: 3)
        XCTAssertEqual(completedEmbed.title, "✅ Focus Block Completed")
        XCTAssertEqual(completedEmbed.color, 0x059669)
        XCTAssertEqual(completedEmbed.fields?.count, 5)

        let bailedEmbed = DiscordMessages.sessionEmbed(subject: "Math", isCompleted: false,
                                                       duration: 600, attempts: 5, tabs: 0, streakDays: 0)
        XCTAssertEqual(bailedEmbed.title, "🏳️ Focus Block Bailed")
        XCTAssertEqual(bailedEmbed.color, 0xE11D48)
        XCTAssertEqual(bailedEmbed.fields?.count, 4)
    }

    func testStartAndCompletedWithMasteryTier() {
        let startText = DiscordMessages.start(name: "Zixuan", subject: "Algorithms", mode: .goal(minutes: 60), tierName: "Specialist")
        XCTAssertEqual(startText, "🔒 **Zixuan** is locked in on **Algorithms** [Specialist] (goal 1h 0m)")

        let completedText = DiscordMessages.completed(
            name: "Zixuan",
            subject: "Algorithms",
            duration: 3600,
            attempts: 0,
            tabs: 0,
            streakDays: 3,
            tierName: "Specialist"
        )
        XCTAssertEqual(
            completedText,
            "✅ **Zixuan** locked in on **Algorithms** [Specialist] for **1h 0m** · tried other apps **0×** · closed **0** tabs · 🔥 3d streak"
        )

        let embed = DiscordMessages.sessionEmbed(
            subject: "Algorithms",
            isCompleted: true,
            duration: 3600,
            attempts: 0,
            tabs: 0,
            streakDays: 3,
            tierName: "Specialist"
        )
        XCTAssertEqual(embed.fields?.count, 6)
        XCTAssertEqual(embed.fields?.first { $0.name == "Tier" }?.value, "Specialist")
    }
}
