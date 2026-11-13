import XCTest
@testable import Tofu

@MainActor
final class PlanningModeTests: XCTestCase {
    private func makeStore() throws -> Store {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlanningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return Store(fileURL: directory.appendingPathComponent("store.json"))
    }

    func testPlanningSetupHasDedicatedIDAndAllowlists() {
        let setup = Subject.planningSetup(feedURL: "https://news.ycombinator.com")
        XCTAssertEqual(setup.id, Subject.planningID)
        XCTAssertEqual(setup.name, "Planning Mode")
        XCTAssertEqual(setup.sites, ["https://news.ycombinator.com"])

        let allowedBundleIDs = Set(setup.allowedApps.map(\.bundleID))
        XCTAssertTrue(allowedBundleIDs.contains("com.apple.MobileSMS"))
        XCTAssertTrue(allowedBundleIDs.contains("com.tinyspeck.slackmacgap"))
        XCTAssertTrue(allowedBundleIDs.contains("ru.keepcoder.Telegram"))
        XCTAssertTrue(allowedBundleIDs.contains("com.hnc.Discord"))
    }

    func testAppModelResolvesPlanningSetupWithoutExposingInSubjects() throws {
        let h = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: h.engine)

        XCTAssertFalse(model.data.subjects.contains { $0.id == Subject.planningID })
        let resolved = model.subject(id: Subject.planningID)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, Subject.planningID)
    }

    func testDiscordBudgetDecrementsWhenDiscordIsActive() async {
        let h = EngineHarness()
        var frontmostApp: String? = "com.hnc.Discord"
        h.engine.activeAppBundleID = { frontmostApp }

        let setup = Subject.planningSetup()
        await h.engine.start(subject: setup, mode: .goal(minutes: 15), displayName: "Alex")

        XCTAssertTrue(h.engine.isPlanningMode)
        XCTAssertEqual(h.engine.discordBudgetRemaining, 5 * 60)

        // Tick 10 times while Discord is active
        for _ in 0..<10 {
            h.engine.tick()
        }
        XCTAssertEqual(h.engine.discordBudgetRemaining, 5 * 60 - 10)

        // Switch to Messages; Discord budget should stay put
        frontmostApp = "com.apple.MobileSMS"
        for _ in 0..<5 {
            h.engine.tick()
        }
        XCTAssertEqual(h.engine.discordBudgetRemaining, 5 * 60 - 10)
    }

    func testDiscordCutoffWhenBudgetExhausted() async {
        let h = EngineHarness()
        let frontmostApp = "com.hnc.Discord"
        h.engine.activeAppBundleID = { frontmostApp }

        let setup = Subject.planningSetup()
        await h.engine.start(subject: setup, mode: .goal(minutes: 15), displayName: "Alex")

        XCTAssertTrue(h.blocker.startedWith?.contains("com.hnc.Discord") == true)

        // Fast forward 300 ticks
        for _ in 0..<300 {
            h.engine.tick()
        }

        XCTAssertEqual(h.engine.discordBudgetRemaining, 0)
        XCTAssertFalse(h.blocker.startedWith?.contains("com.hnc.Discord") == true)
        XCTAssertTrue(h.chrome.closedHosts.contains("discord.com"))
        XCTAssertTrue(h.toaster.messages.contains { $0.contains("Discord 5-minute planning budget reached") })
    }
}
