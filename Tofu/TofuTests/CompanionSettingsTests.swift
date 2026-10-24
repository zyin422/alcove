import XCTest
@testable import Tofu

final class CompanionSettingsTests: XCTestCase {
    func testDefaultsAreEnabledGentle() {
        let settings = AppSettings()
        XCTAssertTrue(settings.companionEnabled)
        XCTAssertEqual(settings.companionPersonality, .gentle)
    }

    /// Settings saved before the companion existed still load, with the new fields at their defaults.
    func testOlderStoreFileFallsBackToCompanionDefaults() throws {
        let json = #"{"displayName":"Alex","discordEnabled":false,"giveUpTemplate":"I give up on {subject}","channelCache":{}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.companionEnabled)
        XCTAssertEqual(settings.companionPersonality, .gentle)
    }

    /// Store files from the anime companion keep loading; the old personalities become gentle.
    func testRetiredAnimePersonalitiesLoadAsGentle() throws {
        for old in ["tsundere", "yandere", "escalation", "something-new"] {
            let json = #"{"displayName":"Alex","discordEnabled":false,"giveUpTemplate":"x","channelCache":{},"companionEnabled":false,"companionPersonality":"\#(old)"}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            XCTAssertEqual(settings.companionPersonality, .gentle, old)
            XCTAssertFalse(settings.companionEnabled)
        }
    }

    func testCompanionFieldsRoundTrip() throws {
        var settings = AppSettings()
        settings.companionEnabled = false
        settings.companionPersonality = .wise
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.companionEnabled)
        XCTAssertEqual(decoded.companionPersonality, .wise)
    }
}
