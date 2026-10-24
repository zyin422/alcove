import CoreServices
import XCTest
@testable import Tofu

final class SetupCheckTests: XCTestCase {
    private let allGood = SetupCheck.Inputs(accessibility: true, chrome: .allowed, openAIKey: .keychain,
                                            discordEnabled: true, discordToken: .teamFile, googleConnected: true,
                                            screenMemoryEnabled: true, screenRecording: true)

    func testEverythingReady() {
        let items = SetupCheck.items(allGood)
        XCTAssertEqual(items.map(\.title),
                       ["Accessibility", "Chrome control", "OpenAI key", "Discord", "Screen memory", "Google"])
        XCTAssertTrue(items.allSatisfy { $0.state == .ready })
        XCTAssertEqual(SetupCheck.summary(items), "6 of 6 ready")
    }

    func testMissingPermissionsNeedAction() {
        var inputs = allGood
        inputs.accessibility = false
        inputs.chrome = .denied
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[0].state, .needsAction)
        XCTAssertEqual(items[1].state, .needsAction)
        XCTAssertEqual(SetupCheck.summary(items), "4 of 6 ready")
    }

    func testOptionalThingsCountAsReady() {
        var inputs = allGood
        inputs.openAIKey = .none
        inputs.discordEnabled = false
        inputs.googleConnected = false
        inputs.screenMemoryEnabled = false
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[2].state, .optional)
        XCTAssertEqual(items[3].state, .optional)
        XCTAssertEqual(items[4].state, .optional)
        XCTAssertEqual(items[5].state, .optional)
        XCTAssertEqual(SetupCheck.summary(items), "6 of 6 ready")
    }

    func testDiscordOnWithoutTokenNeedsAction() {
        var inputs = allGood
        inputs.discordToken = .none
        XCTAssertEqual(SetupCheck.items(inputs)[3].state, .needsAction)
    }

    func testChromeNotRunningIsUnknownAndNotCounted() {
        var inputs = allGood
        inputs.chrome = .appNotRunning
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[1].state, .unknown)
        XCTAssertEqual(SetupCheck.summary(items), "5 of 6 ready")
    }

    func testScreenMemoryNeedsPermissionAndKey() {
        var inputs = allGood
        inputs.screenRecording = false
        XCTAssertEqual(SetupCheck.items(inputs)[4].state, .needsAction)
        inputs.screenRecording = true
        inputs.openAIKey = .none
        XCTAssertEqual(SetupCheck.items(inputs)[4].state, .needsAction)
    }

    func testAutomationStatusMapping() {
        XCTAssertEqual(AutomationPermission.from(status: noErr), .allowed)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(procNotFound)), .appNotRunning)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(errAEEventWouldRequireUserConsent)), .notAsked)
    }
}
