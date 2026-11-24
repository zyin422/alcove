import XCTest
@testable import Tofu

final class ModelsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testPresetSiteCountsAndAppZones() {
        XCTAssertEqual(LayoutPreset.split.siteCount, 2)
        XCTAssertEqual(LayoutPreset.full.siteCount, 1)
        XCTAssertEqual(LayoutPreset.thirds.siteCount, 2)
        XCTAssertEqual(LayoutPreset.mainSide.siteCount, 1)
        XCTAssertFalse(LayoutPreset.split.appHasZone)
        XCTAssertFalse(LayoutPreset.full.appHasZone)
        XCTAssertTrue(LayoutPreset.thirds.appHasZone)
        XCTAssertTrue(LayoutPreset.mainSide.appHasZone)
    }

    func testPresetTitlesAndOrder() {
        XCTAssertEqual(LayoutPreset.allCases, [.split, .full, .thirds, .mainSide])
        XCTAssertEqual(LayoutPreset.allCases.map(\.title), ["Left / Right", "Full", "Thirds", "70 / 30"])
        XCTAssertEqual(LayoutPreset.mainSide.id, "mainSide")
    }

    func testSessionModeGoalAccessors() {
        XCTAssertNil(SessionMode.open.goalMinutes)
        XCTAssertNil(SessionMode.open.goalSeconds)
        XCTAssertEqual(SessionMode.goal(minutes: 25).goalMinutes, 25)
        XCTAssertEqual(SessionMode.goal(minutes: 25).goalSeconds, 1500)
    }

    func testSessionModeCodableRoundTripBothCases() throws {
        for mode in [SessionMode.open, SessionMode.goal(minutes: 50)] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SessionMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testSessionDefaultsHeartbeatToStart() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0)
        XCTAssertEqual(session.lastHeartbeat, t0)
        XCTAssertNil(session.end)
        XCTAssertNil(session.outcome)
        XCTAssertEqual(session.blockedAttempts, 0)
        XCTAssertEqual(session.closedTabs, 0)
        XCTAssertFalse(session.isDemo)
        XCTAssertEqual(session.duration, 0)
    }

    func testDurationUsesLastHeartbeatWhileActive() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0,
                              lastHeartbeat: t0.addingTimeInterval(90))
        XCTAssertEqual(session.duration, 90)
    }

    func testDurationUsesEndWhenFinished() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .goal(minutes: 25), start: t0,
                              end: t0.addingTimeInterval(1500), lastHeartbeat: t0.addingTimeInterval(1490),
                              outcome: .completed)
        XCTAssertEqual(session.duration, 1500)
    }

    func testDurationIsNeverNegative() {
        let session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: t0,
                              end: t0.addingTimeInterval(-30))
        XCTAssertEqual(session.duration, 0)
    }

    func testAppSettingsDefaults() {
        let settings = AppSettings(displayName: "Alex")
        XCTAssertEqual(settings.displayName, "Alex")
        XCTAssertFalse(settings.discordEnabled)
        XCTAssertEqual(settings.giveUpTemplate, "I give up on {subject}")
        XCTAssertEqual(settings.channelCache, [:])
        XCTAssertFalse(settings.allowOffTaskDuringBreak)
        XCTAssertEqual(settings.dailyTargetMinutes, 4 * 60)
    }

    func testAppSettingsDailyTargetMinutesCodableWithFallback() throws {
        // Legacy JSON without dailyTargetMinutes
        let legacyJSON = Data(#"{"displayName":"Alex"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(decoded.dailyTargetMinutes, 240)

        // Custom daily target (6 hours = 360m)
        var custom = AppSettings()
        custom.dailyTargetMinutes = 360
        let encoded = try JSONEncoder().encode(custom)
        let roundtrip = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(roundtrip.dailyTargetMinutes, 360)
    }

    func testEmptyStoreData() {
        let empty = StoreData.empty
        XCTAssertEqual(empty.version, 1)
        XCTAssertTrue(empty.subjects.isEmpty)
        XCTAssertTrue(empty.sessions.isEmpty)
    }

    func testSessionNotesCodableBackwardsCompatibility() throws {
        // Legacy JSON without notes
        let legacyJSON = """
        {"id":"B621E1F8-C36C-495A-93FC-0C247A3E6E5F","subjectID":"C621E1F8-C36C-495A-93FC-0C247A3E6E5F","subjectName":"CS128","mode":{"open":{}},"start":1760000000}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Session.self, from: legacyJSON)
        XCTAssertEqual(decoded.subjectName, "CS128")
        XCTAssertNil(decoded.notes)

        // New session with notes
        var session = Session(subjectID: UUID(), subjectName: "CS128", mode: .open, start: Date())
        session.notes = "Completed compiler AST visitor implementation"
        let encoded = try JSONEncoder().encode(session)
        let roundtrip = try JSONDecoder().decode(Session.self, from: encoded)
        XCTAssertEqual(roundtrip.notes, "Completed compiler AST visitor implementation")
    }

    func testSubjectDefaults() {
        let subject = Subject(name: "CS128")
        XCTAssertEqual(subject.details, "")
        XCTAssertEqual(subject.preset, .split)
        XCTAssertEqual(subject.colorHex, SubjectColor.hex(for: "CS128"))
        XCTAssertTrue(SubjectColor.palette.contains(subject.colorHex))
        XCTAssertEqual(SubjectColor.canonical("FFFFFF", name: "CS128"), SubjectColor.hex(for: "CS128"))
        XCTAssertEqual(SubjectColor.canonical("e45756", name: "CS128"), "E45756")
        let assigned = SubjectColor.assigned([
            ("CS128", SubjectColor.palette[0]),
            ("MATH241", SubjectColor.palette[0]),
        ])
        XCTAssertEqual(assigned, [SubjectColor.palette[0], SubjectColor.palette[1]])
        XCTAssertEqual(subject.sites, [])
        XCTAssertEqual(subject.allowedApps, [])
        XCTAssertEqual(subject.extraDomains, [])
        XCTAssertEqual(AllowedApp(bundleID: "com.apple.Notes", name: "Notes").id, "com.apple.Notes")
    }

}
