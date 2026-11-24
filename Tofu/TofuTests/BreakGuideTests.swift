import XCTest
@testable import Tofu

final class BreakGuideTests: XCTestCase {
    func testBoxBreathingCycleTransitions() {
        // Box breathing is 4-4-4-4 (16s cycle)
        // 0.0s -> Inhale
        let state0 = BreakGuide.breathingState(technique: .box, cycleElapsed: 0.0)
        XCTAssertEqual(state0.phase, .inhale)
        XCTAssertEqual(state0.phaseDuration, 4.0)
        XCTAssertEqual(state0.progress, 0.0)

        // 2.0s -> Inhale (50%)
        let state2 = BreakGuide.breathingState(technique: .box, cycleElapsed: 2.0)
        XCTAssertEqual(state2.phase, .inhale)
        XCTAssertEqual(state2.progress, 0.5, accuracy: 0.001)

        // 5.0s -> HoldIn (1s into 4s hold = 25%)
        let state5 = BreakGuide.breathingState(technique: .box, cycleElapsed: 5.0)
        XCTAssertEqual(state5.phase, .holdIn)
        XCTAssertEqual(state5.progress, 0.25, accuracy: 0.001)

        // 9.0s -> Exhale (1s into 4s exhale = 25%)
        let state9 = BreakGuide.breathingState(technique: .box, cycleElapsed: 9.0)
        XCTAssertEqual(state9.phase, .exhale)

        // 13.0s -> HoldOut (1s into 4s hold = 25%)
        let state13 = BreakGuide.breathingState(technique: .box, cycleElapsed: 13.0)
        XCTAssertEqual(state13.phase, .holdOut)

        // 16.0s -> wraps back to Inhale
        let state16 = BreakGuide.breathingState(technique: .box, cycleElapsed: 16.0)
        XCTAssertEqual(state16.phase, .inhale)
    }

    func testRelaxBreathingCycleTransitions() {
        // 4-7-8 relaxing breathing (19s cycle)
        let totalCycle = BreakGuide.cycleDuration(for: .relax)
        XCTAssertEqual(totalCycle, 19.0)

        let stateInhale = BreakGuide.breathingState(technique: .relax, cycleElapsed: 2.0)
        XCTAssertEqual(stateInhale.phase, .inhale)

        let stateHold = BreakGuide.breathingState(technique: .relax, cycleElapsed: 6.0)
        XCTAssertEqual(stateHold.phase, .holdIn)
        XCTAssertEqual(stateHold.phaseDuration, 7.0)

        let stateExhale = BreakGuide.breathingState(technique: .relax, cycleElapsed: 15.0)
        XCTAssertEqual(stateExhale.phase, .exhale)
        XCTAssertEqual(stateExhale.phaseDuration, 8.0)
    }

    func testErgonomicStretchesCatalog() {
        let list = BreakGuide.stretches
        XCTAssertGreaterThanOrEqual(list.count, 3)
        XCTAssertTrue(list.contains { $0.title.contains("Neck") })
        XCTAssertTrue(list.contains { $0.title.contains("Shoulder") || $0.title.contains("Chest") })
        XCTAssertTrue(list.contains { $0.title.contains("Wrist") })
    }
}
