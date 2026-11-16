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
        XCTAssertEqual(DistractionApps.category(of: "com.netflix.Netflix"), .streaming)
        XCTAssertEqual(DistractionApps.category(of: "com.apple.TV"), .streaming)
        XCTAssertEqual(DistractionApps.category(of: "com.apple.GameCenter"), .entertainment)
        XCTAssertEqual(DistractionApps.category(of: "com.apple.Safari"), .browsers)
        XCTAssertEqual(DistractionApps.category(of: "org.mozilla.firefox"), .browsers)
        XCTAssertEqual(DistractionApps.category(of: "com.supercell.clashroyale"), .gaming)
        XCTAssertEqual(DistractionApps.category(of: "com.apple.Chess"), .gaming)
    }

    func testProductivityAppsAndLookalikesAreNotDistractions() {
        XCTAssertNil(DistractionApps.category(of: "com.apple.dt.Xcode"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.calculator"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.Preview"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.Terminal"))
        XCTAssertNil(DistractionApps.category(of: "com.spotify.client"))
        XCTAssertNil(DistractionApps.category(of: "com.apple.Music"))
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

    func testAllUnmonitoredBrowsersAreDistractions() {
        let browsers = ["com.apple.Safari", "org.mozilla.firefox", "com.operasoftware.Opera",
                        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi",
                        "org.torproject.torbrowser"]
        for id in browsers {
            XCTAssertEqual(DistractionApps.category(of: id), .browsers, "\(id) must be categorized as unmonitored browser")
            XCTAssertTrue(DistractionApps.isDistraction(id))
        }
    }

    func testGamingAppsAreDistractions() {
        let games = ["com.valvesoftware.steam", "com.epicgames.EpicGamesLauncher", "net.battle.app",
                     "com.riotgames.LeagueofLegends.LeagueClientUx", "com.mojang.minecraftlauncher",
                     "com.Roblox.RobloxPlayer", "com.apple.Chess", "com.supercell.clashroyale"]
        for id in games {
            XCTAssertEqual(DistractionApps.category(of: id), .gaming, "\(id) must be categorized as gaming")
            XCTAssertTrue(DistractionApps.isDistraction(id))
        }
    }
}
