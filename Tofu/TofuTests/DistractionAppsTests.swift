import XCTest
@testable import Tofu

final class DistractionAppsTests: XCTestCase {
    func testEachCategoryHasItsApps() {
        XCTAssertEqual(DistractionApps.category(of: "com.hnc.Discord"), .messaging)
        XCTAssertEqual(DistractionApps.category(of: "ru.keepcoder.Telegram"), .messaging)
        XCTAssertEqual(DistractionApps.category(of: "com.tinyspeck.slackmacgap"), .messaging)
        XCTAssertEqual(DistractionApps.category(of: "com.apple.MobileSMS"), .messaging)
        XCTAssertEqual(DistractionApps.category(of: "com.atebits.Tweetie2"), .social)
        XCTAssertEqual(DistractionApps.category(of: "com.valvesoftware.steam"), .gaming)
        XCTAssertEqual(DistractionApps.category(of: "com.epicgames.EpicGamesLauncher"), .gaming)
        XCTAssertEqual(DistractionApps.category(of: "com.spotify.client"), .streaming)
        XCTAssertEqual(DistractionApps.category(of: "com.apple.GameCenter"), .entertainment)
    }

    func testProductivityAppsAndLookalikesAreNotDistractions() {
        XCTAssertNil(DistractionApps.category(of: "com.apple.dt.Xcode"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.calculator"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.Preview"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.Terminal"))
        XCTAssertNil(DistractionApps.category(of: ""))
    }

    func testCaseInsensitiveMatching() {
        XCTAssertTrue(DistractionApps.isDistraction("COM.HNC.DISCORD"))
        XCTAssertTrue(DistractionApps.isDistraction("com.Valvesoftware.Steam"))
        XCTAssertFalse(DistractionApps.isDistraction("com.apple.dt.xcode"))
    }

    func testAllBundleIDsArePopulated() {
        let all = DistractionApps.allBundleIDs
        XCTAssertFalse(all.isEmpty)
        for category in DistractionApps.Category.allCases {
            XCTAssertFalse(DistractionApps.apps[category]?.isEmpty ?? true, category.rawValue)
        }
    }
}
