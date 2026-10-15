import XCTest
@testable import Tofu

final class CompanionSettingsTests: XCTestCase {
    func testDefaultsAreEnabledEscalation() {
        let settings = AppSettings()
        XCTAssertTrue(settings.companionEnabled)
        XCTAssertEqual(settings.companionPersonality, .escalation)
    }

    /// Settings saved before the companion existed still load, with the new fields at their defaults.
    func testOlderStoreFileFallsBackToCompanionDefaults() throws {
        let json = #"{"displayName":"Alex","discordEnabled":false,"giveUpTemplate":"I give up on {subject}","channelCache":{}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.companionEnabled)
        XCTAssertEqual(settings.companionPersonality, .escalation)
    }

    func testCompanionFieldsRoundTrip() throws {
        var settings = AppSettings()
        settings.companionEnabled = false
        settings.companionPersonality = .yandere
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.companionEnabled)
        XCTAssertEqual(decoded.companionPersonality, .yandere)
    }
}
