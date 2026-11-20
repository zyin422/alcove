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
        XCTAssertEqual(setup.browser, .arc)

        let allowedBundleIDs = Set(setup.allowedApps.map(\.bundleID))
        XCTAssertTrue(allowedBundleIDs.contains("company.thebrowser.Browser"))
        XCTAssertTrue(allowedBundleIDs.contains("com.meta.endo"))
        XCTAssertTrue(allowedBundleIDs.contains("com.google.antigravity"))
        XCTAssertTrue(allowedBundleIDs.contains("com.google.antigravity-ide"))
        XCTAssertTrue(allowedBundleIDs.contains("com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(allowedBundleIDs.contains("com.apple.dt.Xcode"))
        XCTAssertFalse(allowedBundleIDs.contains("com.hnc.Discord"))
        XCTAssertFalse(allowedBundleIDs.contains("com.google.Chrome"))
    }

    func testAppModelResolvesPlanningSetupWithoutExposingInSubjects() throws {
        let h = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: h.engine)

        XCTAssertFalse(model.data.subjects.contains { $0.id == Subject.planningID })
        let resolved = model.subject(id: Subject.planningID)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.id, Subject.planningID)
        XCTAssertEqual(resolved?.browser, .arc)
    }

    func testPlanningModeBlocksDiscordAndEnforcesArc() {
        let setup = Subject.planningSetup()
        let allowed = BlockPolicy.allowedSet(for: setup, ownBundleID: "com.tofu.app")

        XCTAssertTrue(allowed.contains("company.thebrowser.Browser"))
        XCTAssertTrue(allowed.contains("com.meta.endo"))
        XCTAssertTrue(allowed.contains("com.google.antigravity"))
        XCTAssertFalse(allowed.contains("com.hnc.Discord"))
        XCTAssertFalse(allowed.contains("com.google.Chrome"))

        let discord = RunningAppInfo(bundleID: "com.hnc.Discord", name: "Discord", isRegular: true)
        XCTAssertTrue(BlockPolicy.shouldBlock(discord, allowed: allowed))

        let arc = RunningAppInfo(bundleID: "company.thebrowser.Browser", name: "Arc", isRegular: true)
        XCTAssertFalse(BlockPolicy.shouldBlock(arc, allowed: allowed))
    }

    func testPlanningModeDailyQuotaPreventsSpam() async throws {
        let h = EngineHarness()
        let model = AppModel(store: try makeStore(), engine: h.engine)

        XCTAssertTrue(model.canPlanToday)
        await model.startPlanningMode()

        XCTAssertFalse(model.canPlanToday)
        XCTAssertTrue(h.engine.isPlanningMode)

        // Reset engine locked state to test second invocation
        await h.engine.finish()
        XCTAssertFalse(h.engine.isLocked)

        // Attempting to start planning mode again should be rejected by the daily quota
        await model.startPlanningMode()
        XCTAssertFalse(h.engine.isLocked)
    }
}
