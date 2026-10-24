import CoreServices
import XCTest
@testable import Tofu

final class SetupCheckTests: XCTestCase {
    private let allGood = SetupCheck.Inputs(accessibility: true, chrome: .allowed, openAIKey: .keychain,
                                            discordEnabled: true, discordToken: .teamFile, googleConnected: true,
                                            screenMemoryEnabled: true, screenRecording: true,
                                            googleServices: [.calendar, .tasks, .gmail])

    func testEverythingReady() {
        let items = SetupCheck.items(allGood)
        XCTAssertEqual(items.map(\.title), ["Accessibility", "Chrome control", "Discord", "Screen memory", "Google"])
        XCTAssertTrue(items.allSatisfy { $0.state == .ready })
        XCTAssertEqual(SetupCheck.summary(items), "5 of 5 ready")
    }

    func testThereIsNoOpenAIKeyRow() {
        var inputs = allGood
        inputs.openAIKey = .none
        inputs.screenMemoryEnabled = false
        let items = SetupCheck.items(inputs)
        XCTAssertFalse(items.contains { $0.title.contains("OpenAI") })
        XCTAssertEqual(SetupCheck.summary(items), "5 of 5 ready")
    }

    func testMissingPermissionsNeedAction() {
        var inputs = allGood
        inputs.accessibility = false
        inputs.chrome = .denied
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[0].state, .needsAction)
        XCTAssertEqual(items[1].state, .needsAction)
        XCTAssertEqual(SetupCheck.summary(items), "3 of 5 ready")
    }

    func testOptionalThingsCountAsReady() {
        var inputs = allGood
        inputs.discordEnabled = false
        inputs.googleConnected = false
        inputs.screenMemoryEnabled = false
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[2].state, .optional)
        XCTAssertEqual(items[3].state, .optional)
        XCTAssertEqual(items[4].state, .optional)
        XCTAssertEqual(SetupCheck.summary(items), "5 of 5 ready")
    }

    func testDiscordOnWithoutTokenNeedsAction() {
        var inputs = allGood
        inputs.discordToken = .none
        XCTAssertEqual(SetupCheck.items(inputs)[2].state, .needsAction)
    }

    func testChromeNotRunningIsUnknownAndNotCounted() {
        var inputs = allGood
        inputs.chrome = .appNotRunning
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[1].state, .unknown)
        XCTAssertEqual(SetupCheck.summary(items), "4 of 5 ready")
    }

    func testScreenMemoryNeedsPermissionAndKey() {
        var inputs = allGood
        inputs.screenRecording = false
        XCTAssertEqual(SetupCheck.items(inputs)[3].state, .needsAction)
        inputs.screenRecording = true
        inputs.openAIKey = .none
        XCTAssertEqual(SetupCheck.items(inputs)[3].state, .needsAction)
        XCTAssertTrue(SetupCheck.items(inputs)[3].detail.contains("OpenAI key"))
    }

    func testGoogleRowNamesServicesAndPointsToConnections() {
        var inputs = allGood
        XCTAssertEqual(SetupCheck.items(inputs)[4].detail, "Calendar, Tasks and Gmail on · Manage in Connections")
        inputs.googleServices = [.calendar]
        XCTAssertEqual(SetupCheck.items(inputs)[4].detail, "Calendar on · Manage in Connections")
        inputs.googleServices = []
        XCTAssertEqual(SetupCheck.items(inputs)[4].detail, "Connected, every service is off · Manage in Connections")
        inputs.googleConnected = false
        XCTAssertEqual(SetupCheck.items(inputs)[4].detail, "Not connected (optional) · Manage in Connections")
    }

    func testGoogleTokenWithoutGmailAsksToReconnect() {
        var inputs = allGood
        inputs.googleServices = [.calendar, .tasks]
        inputs.googleNotGranted = [.gmail]
        let item = SetupCheck.items(inputs)[4]
        XCTAssertEqual(item.state, .optional)
        XCTAssertEqual(item.detail, "Reconnect to enable Gmail · Manage in Connections")
    }

    func testAutomationStatusMapping() {
        XCTAssertEqual(AutomationPermission.from(status: noErr), .allowed)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(procNotFound)), .appNotRunning)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(errAEEventWouldRequireUserConsent)), .notAsked)
    }
}
