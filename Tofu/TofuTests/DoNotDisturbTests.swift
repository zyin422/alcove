import XCTest
@testable import Tofu

final class DoNotDisturbTests: XCTestCase {
    private let installed: Set<String> = [DoNotDisturbPlan.onName, DoNotDisturbPlan.offName]

    func testManageWhenBothShortcutsAreInstalledAndNoFocusIsOn() {
        XCTAssertEqual(DoNotDisturbPlan.decide(installed: installed, focusIsOn: false), .manage)
    }

    func testLeaveAnExistingFocusAlone() {
        XCTAssertEqual(DoNotDisturbPlan.decide(installed: installed, focusIsOn: true), .alreadyOn)
    }

    func testAskToInstallWhenEitherShortcutIsMissing() {
        XCTAssertEqual(DoNotDisturbPlan.decide(installed: [DoNotDisturbPlan.onName], focusIsOn: false), .needsInstall)
        XCTAssertEqual(DoNotDisturbPlan.decide(installed: [DoNotDisturbPlan.offName], focusIsOn: true), .needsInstall)
        XCTAssertEqual(DoNotDisturbPlan.decide(installed: [], focusIsOn: false), .needsInstall)
    }

    func testOnShortcutTurnsOnDoNotDisturbUntilItIsTurnedOff() throws {
        let workflow = DoNotDisturbPlan.workflow(name: DoNotDisturbPlan.onName, enabled: true)
        let action = try actionParameters(workflow)

        XCTAssertEqual(workflow["WFWorkflowName"] as? String, DoNotDisturbPlan.onName)
        XCTAssertEqual(action["Enabled"] as? Bool, true)
        XCTAssertEqual(action["AssertionType"] as? String, "Turned Off")
        let mode = try XCTUnwrap(action["FocusModes"] as? [String: Any])
        XCTAssertEqual(mode["Identifier"] as? String, DoNotDisturbPlan.modeIdentifier)
        XCTAssertEqual(mode["DisplayString"] as? String, "Do Not Disturb")
    }

    func testOffShortcutTurnsDoNotDisturbOff() throws {
        let workflow = DoNotDisturbPlan.workflow(name: DoNotDisturbPlan.offName, enabled: false)
        let action = try actionParameters(workflow)

        XCTAssertEqual(workflow["WFWorkflowName"] as? String, DoNotDisturbPlan.offName)
        XCTAssertEqual(action["Enabled"] as? Bool, false)
        XCTAssertNil(action["AssertionType"])
        let mode = try XCTUnwrap(action["FocusModes"] as? [String: Any])
        XCTAssertEqual(mode["Identifier"] as? String, DoNotDisturbPlan.modeIdentifier)
    }

    func testWorkflowIsAPropertyList() throws {
        let on = DoNotDisturbPlan.workflow(name: DoNotDisturbPlan.onName, enabled: true)
        let off = DoNotDisturbPlan.workflow(name: DoNotDisturbPlan.offName, enabled: false)
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: on, format: .binary, options: 0))
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: off, format: .binary, options: 0))
    }

    private func actionParameters(_ workflow: [String: Any]) throws -> [String: Any] {
        let actions = try XCTUnwrap(workflow["WFWorkflowActions"] as? [[String: Any]])
        XCTAssertEqual(actions.first?["WFWorkflowActionIdentifier"] as? String, "is.workflow.actions.dnd.set")
        return try XCTUnwrap(actions.first?["WFWorkflowActionParameters"] as? [String: Any])
    }
}
