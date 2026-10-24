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

    // MARK: Setup is never forced on the user

    /// Records client calls. `run` and `install` are called from background tasks, so access is locked.
    private final class ClientLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _notes: [String] = []
        private var _installs = 0
        private var _runs: [String] = []
        var notes: [String] { lock.withLock { _notes } }
        var installs: Int { lock.withLock { _installs } }
        var runs: [String] { lock.withLock { _runs } }
        func note(_ text: String) { lock.withLock { _notes.append(text) } }
        func install() { lock.withLock { _installs += 1 } }
        func run(_ name: String) { lock.withLock { _runs.append(name) } }
    }

    @MainActor
    private func controller(installed: Set<String>, log: ClientLog, defaults: UserDefaults) -> ShortcutDoNotDisturb {
        ShortcutDoNotDisturb(client: DoNotDisturbClient(
            shortcutNames: { installed },
            focusIsOn: { false },
            run: { name in log.run(name); return true },
            install: { log.install(); return true },
            notify: { note in log.note(note) }), defaults: defaults)
    }

    @MainActor
    func testMissingShortcutsShowOneHintEverAndNeverOpenShortcuts() async throws {
        let suite = "dnd-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ClientLog()

        let first = controller(installed: [], log: log, defaults: defaults)
        first.beginBlock()
        try await Task.sleep(nanoseconds: 300_000_000)
        first.endBlock()
        // A relaunch: a new controller with the same remembered defaults.
        let second = controller(installed: [], log: log, defaults: defaults)
        second.beginBlock()
        try await Task.sleep(nanoseconds: 300_000_000)
        second.endBlock()

        XCTAssertEqual(log.notes, [DoNotDisturbPlan.setupHint])
        XCTAssertEqual(log.installs, 0)
        XCTAssertTrue(log.runs.isEmpty)
    }

    @MainActor
    func testInstalledShortcutsTurnDoNotDisturbOnWithoutAHint() async throws {
        let suite = "dnd-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ClientLog()
        let dnd = controller(installed: [DoNotDisturbPlan.onName, DoNotDisturbPlan.offName], log: log, defaults: defaults)
        dnd.beginBlock()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(log.runs, [DoNotDisturbPlan.onName])
        XCTAssertTrue(log.notes.isEmpty)
        XCTAssertEqual(log.installs, 0)
    }
}
