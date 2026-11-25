import XCTest
@testable import Alcove

final class GoogleModelsTests: XCTestCase {
    func testPriorityWithoutGoogleTaskIDStillDecodes() throws {
        let old = Data(#"{"id":"\#(UUID().uuidString)","title":"Read ch. 3","isDone":false}"#.utf8)
        let priority = try JSONDecoder().decode(Priority.self, from: old)
        XCTAssertNil(priority.googleTaskID)
        XCTAssertEqual(priority.title, "Read ch. 3")
    }

    func testPriorityGoogleTaskIDRoundTrips() throws {
        var priority = Priority(title: "PS4")
        priority.googleTaskID = "gt-1"
        let decoded = try JSONDecoder().decode(Priority.self, from: JSONEncoder().encode(priority))
        XCTAssertEqual(decoded.googleTaskID, "gt-1")
    }

    func testOldSettingsDecodeWithGoogleDefaults() throws {
        let old = Data(#"{"displayName":"Ax","discordEnabled":true,"giveUpTemplate":"x","channelCache":{}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertTrue(settings.googleTasksSyncEnabled)
        XCTAssertTrue(settings.googleSessionLogEnabled)
        XCTAssertTrue(settings.googleShowEventsEnabled)
        XCTAssertNil(settings.googleCalendarID)
    }

    func testSettingsGoogleFieldsRoundTrip() throws {
        var settings = AppSettings()
        settings.googleTasksSyncEnabled = false
        settings.googleCalendarID = "cal-9"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.googleTasksSyncEnabled)
        XCTAssertEqual(decoded.googleCalendarID, "cal-9")
    }
}
