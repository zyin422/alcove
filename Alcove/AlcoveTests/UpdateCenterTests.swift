import XCTest
@testable import Alcove

@MainActor final class FakeUpdateDriver: UpdateDriving {
    private(set) var checks = 0
    func checkForUpdates() { checks += 1 }
}

/// The sidebar update card's rules: when it shows, when it hides, and what its buttons ask Sparkle to do.
@MainActor final class UpdateCenterTests: XCTestCase {
    func testStartsWithNoCard() {
        XCTAssertNil(UpdateCenter(driver: FakeUpdateDriver()).availableVersion)
    }

    func testFoundUpdateShowsCard() {
        let center = UpdateCenter(driver: FakeUpdateDriver())
        center.updateFound(version: "1.2")
        XCTAssertEqual(center.availableVersion, "1.2")
    }

    func testDismissedVersionStaysHidden() {
        let center = UpdateCenter(driver: FakeUpdateDriver())
        center.updateFound(version: "1.2")
        center.dismiss()
        XCTAssertNil(center.availableVersion)
        center.updateFound(version: "1.2")
        XCTAssertNil(center.availableVersion)
    }

    func testNewerVersionShowsAfterDismiss() {
        let center = UpdateCenter(driver: FakeUpdateDriver())
        center.updateFound(version: "1.2")
        center.dismiss()
        center.updateFound(version: "1.3")
        XCTAssertEqual(center.availableVersion, "1.3")
    }

    func testDismissWithoutCardKeepsEarlierDismissal() {
        let center = UpdateCenter(driver: FakeUpdateDriver())
        center.updateFound(version: "1.2")
        center.dismiss()
        center.dismiss()
        center.updateFound(version: "1.2")
        XCTAssertNil(center.availableVersion)
    }

    func testCheckNowHidesCardAndAsksDriverOnce() {
        let driver = FakeUpdateDriver()
        let center = UpdateCenter(driver: driver)
        center.updateFound(version: "1.2")
        center.checkNow()
        XCTAssertNil(center.availableVersion)
        XCTAssertEqual(driver.checks, 1)
    }

    func testHideDoesNotDismiss() {
        let center = UpdateCenter(driver: FakeUpdateDriver())
        center.updateFound(version: "1.2")
        center.hide()
        XCTAssertNil(center.availableVersion)
        center.updateFound(version: "1.2")
        XCTAssertEqual(center.availableVersion, "1.2")
    }

    func testWithoutDriverCannotCheck() {
        let center = UpdateCenter()
        XCTAssertFalse(center.canCheckForUpdates)
        center.checkNow()
        XCTAssertNil(center.availableVersion)
    }

    func testSettingDriverEnablesChecks() {
        let center = UpdateCenter()
        center.driver = FakeUpdateDriver()
        XCTAssertTrue(center.canCheckForUpdates)
    }

    func testAppModelStartsWithoutUpdater() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateCenter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: Store(fileURL: directory.appendingPathComponent("store.json")),
                             engine: EngineHarness().engine)
        XCTAssertFalse(model.updates.canCheckForUpdates)
        XCTAssertNil(model.updates.availableVersion)
    }
}
