import CoreServices
import XCTest
@testable import Tofu

final class SetupCheckTests: XCTestCase {
    private let allGood = SetupCheck.Inputs(accessibility: true, chrome: .allowed, openAIKey: .keychain,
                                            discordEnabled: true, discordToken: .teamFile, googleConnected: true)

    func testEverythingReady() {
        let items = SetupCheck.items(allGood)
        XCTAssertEqual(items.map(\.title), ["Accessibility", "Chrome control", "OpenAI key", "Discord", "Google"])
        XCTAssertTrue(items.allSatisfy { $0.state == .ready })
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
        inputs.openAIKey = .none
        inputs.discordEnabled = false
        inputs.googleConnected = false
        let items = SetupCheck.items(inputs)
        XCTAssertEqual(items[2].state, .optional)
        XCTAssertEqual(items[3].state, .optional)
        XCTAssertEqual(items[4].state, .optional)
        XCTAssertEqual(SetupCheck.summary(items), "5 of 5 ready")
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
        XCTAssertEqual(SetupCheck.summary(items), "4 of 5 ready")
    }

    func testAutomationStatusMapping() {
        XCTAssertEqual(AutomationPermission.from(status: noErr), .allowed)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(procNotFound)), .appNotRunning)
        XCTAssertEqual(AutomationPermission.from(status: OSStatus(errAEEventWouldRequireUserConsent)), .notAsked)
    }
}
