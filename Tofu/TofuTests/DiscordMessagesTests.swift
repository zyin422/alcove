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
}
