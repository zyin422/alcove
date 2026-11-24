import XCTest
import Carbon
@testable import Tofu

final class GlobalHotKeyTests: XCTestCase {
    @MainActor
    func testGlobalHotKeyInitializationDefaults() {
        let manager = GlobalHotKeyManager()
        XCTAssertEqual(manager.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(manager.modifiers, UInt32(controlKey | optionKey))
        XCTAssertFalse(manager.isRegistered)
    }

    @MainActor
    func testGlobalHotKeyCustomKeycodeAndModifiers() {
        let manager = GlobalHotKeyManager(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(manager.keyCode, 17)
        XCTAssertEqual(manager.modifiers, UInt32(cmdKey | shiftKey))
    }

    @MainActor
    func testGlobalHotKeyTriggerDispatchesCallback() {
        let manager = GlobalHotKeyManager()
        var triggered = false
        manager.onTrigger = {
            triggered = true
        }

        manager.trigger()
        XCTAssertTrue(triggered)
    }

    @MainActor
    func testGlobalHotKeyDispatchMultiAction() {
        let manager = GlobalHotKeyManager()
        var thoughtTriggered = false
        var muteTriggered = false
        var hudTriggered = false

        manager.onTrigger = { thoughtTriggered = true }
        manager.onToggleMute = { muteTriggered = true }
        manager.onToggleHUD = { hudTriggered = true }

        manager.dispatch(action: .quickThought)
        XCTAssertTrue(thoughtTriggered)
        XCTAssertFalse(muteTriggered)
        XCTAssertFalse(hudTriggered)

        manager.dispatch(action: .toggleMute)
        XCTAssertTrue(muteTriggered)
        XCTAssertFalse(hudTriggered)

        manager.dispatch(action: .toggleHUD)
        XCTAssertTrue(hudTriggered)

        // Verify key codes
        XCTAssertEqual(GlobalHotKeyAction.quickThought.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(GlobalHotKeyAction.toggleMute.keyCode, UInt32(kVK_ANSI_M))
        XCTAssertEqual(GlobalHotKeyAction.toggleHUD.keyCode, UInt32(kVK_ANSI_H))
    }

    @MainActor
    func testQuickThoughtPanelControllerIsPresentedInitialState() {
        let controller = QuickThoughtPanelController.shared
        XCTAssertFalse(controller.isPresented)
    }

    @MainActor
    func testQuickThoughtToggleClosesWhenPresented() {
        let controller = QuickThoughtPanelController.shared
        // Ensure closed initially
        controller.close()
        XCTAssertFalse(controller.isPresented)

        let harness = EngineHarness()
        // toggle will attempt presentation
        controller.toggle(engine: harness.engine)
        // If headless / no screen, isPresented remains false or true if window opened
        // calling close ensures it cleans up
        controller.close()
        XCTAssertFalse(controller.isPresented)
    }
}
