import XCTest
@testable import Tofu

final class BlockPolicyTests: XCTestCase {
    private let ownID = "com.tofu.app"
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func subject(apps: [AllowedApp] = []) -> Subject {
        Subject(name: "CS128", allowedApps: apps)
    }

    private func app(_ bundleID: String, regular: Bool = true) -> RunningAppInfo {
        RunningAppInfo(bundleID: bundleID, name: bundleID, isRegular: regular)
    }

    // MARK: allowedSet

    func testAllowedSetIsChromeFinderSystemSettingsOwnAppAndSubjectApps() {
        let notes = AllowedApp(bundleID: "com.apple.Notes", name: "Notes")
        let allowed = BlockPolicy.allowedSet(for: subject(apps: [notes]), ownBundleID: ownID)
        XCTAssertEqual(allowed, ["com.google.Chrome", "com.apple.finder", "com.apple.systempreferences",
                                 ownID, "com.apple.Notes"])
    }

    func testAllowedSetWithoutSubjectAppsStillHasAlwaysAllowedAndOwnApp() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertEqual(allowed, ["com.google.Chrome", "com.apple.finder", "com.apple.systempreferences", ownID])
    }

    func testAllowedSetContainsSystemSettingsSoUsersCanGrantChromeAutomationMidSession() {
        XCTAssertTrue(BlockPolicy.alwaysAllowed.contains("com.apple.systempreferences"))
        XCTAssertTrue(BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID).contains("com.apple.systempreferences"))
    }

    // MARK: shouldBlock

    func testChromeFinderSystemSettingsAndOwnAppAreNeverBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        for id in ["com.google.Chrome", "com.apple.finder", "com.apple.systempreferences", ownID] {
            XCTAssertFalse(BlockPolicy.shouldBlock(app(id), allowed: allowed), id)
        }
    }

    func testSubjectAllowedAppIsNotBlocked() {
        let xcode = AllowedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        let allowed = BlockPolicy.allowedSet(for: subject(apps: [xcode]), ownBundleID: ownID)
        XCTAssertFalse(BlockPolicy.shouldBlock(app("com.apple.dt.Xcode"), allowed: allowed))
    }

    func testNonRegularAppIsNotBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertFalse(BlockPolicy.shouldBlock(app("com.example.menubar", regular: false), allowed: allowed))
    }

    func testEmptyBundleIDIsNotBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertFalse(BlockPolicy.shouldBlock(app(""), allowed: allowed))
    }

    func testDisallowedRegularAppIsBlocked() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        XCTAssertTrue(BlockPolicy.shouldBlock(app("com.hnc.Discord"), allowed: allowed))
        XCTAssertTrue(BlockPolicy.shouldBlock(app("com.apple.Notes"), allowed: allowed))
    }

    func testShouldBlockIsStatelessSoEveryRepeatedAttemptIsHidden() {
        let allowed = BlockPolicy.allowedSet(for: subject(), ownBundleID: ownID)
        let discord = app("com.hnc.Discord")
        XCTAssertEqual((0..<5).map { _ in BlockPolicy.shouldBlock(discord, allowed: allowed) },
                       [true, true, true, true, true])
    }

    // MARK: AttemptDebouncer

    func testFirstAttemptCounts() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
    }

    func testRepeatWithinTwoSecondsDoesNotCount() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(0.5)))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(1.99)))
    }

    func testRepeatAfterTwoSecondsCountsAgain() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(2)))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(3)))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(4.5)))
    }

    func testSuppressedAttemptsDoNotExtendTheWindow() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(1.5)))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(2.1)))
    }

    func testDifferentAppsAreIndependent() {
        var debouncer = AttemptDebouncer()
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertTrue(debouncer.shouldCount("com.apple.Notes", at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(0.2)))
        XCTAssertFalse(debouncer.shouldCount("com.apple.Notes", at: t0.addingTimeInterval(0.3)))
    }

    func testCustomWindow() {
        var debouncer = AttemptDebouncer(window: 10)
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0))
        XCTAssertFalse(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(9)))
        XCTAssertTrue(debouncer.shouldCount("com.hnc.Discord", at: t0.addingTimeInterval(10)))
    }
}
