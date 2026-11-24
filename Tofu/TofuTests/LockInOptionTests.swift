import XCTest
@testable import Tofu

final class LockInOptionTests: XCTestCase {
    func testOptionsInDisplayOrder() {
        XCTAssertEqual(LockInOption.allCases.map(\.title), ["Open-ended", "25 min", "50 min", "90 min", "Custom"])
    }

    func testFixedOptionsMapToModes() {
        XCTAssertEqual(LockInOption.openEnded.mode(customMinutes: 45), .open)
        XCTAssertEqual(LockInOption.minutes25.mode(customMinutes: 45), .goal(minutes: 25))
        XCTAssertEqual(LockInOption.minutes50.mode(customMinutes: 45), .goal(minutes: 50))
        XCTAssertEqual(LockInOption.minutes90.mode(customMinutes: 45), .goal(minutes: 90))
    }

    func testCustomUsesTheTypedMinutesClampedToItsRange() {
        XCTAssertEqual(LockInOption.customRange, 5...240)
        XCTAssertEqual(LockInOption.customRange.lowerBound * 60, Int(DayPlanner.realBlockSeconds))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 45), .goal(minutes: 45))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 5), .goal(minutes: 5))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 1), .goal(minutes: 5))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 0), .goal(minutes: 5))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: -7), .goal(minutes: 5))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 240), .goal(minutes: 240))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 500), .goal(minutes: 240))
    }

    func testClampedMinutesKeepsTypedValuesInRange() {
        XCTAssertEqual(LockInOption.clampedMinutes(0), 5)
        XCTAssertEqual(LockInOption.clampedMinutes(1), 5)
        XCTAssertEqual(LockInOption.clampedMinutes(4), 5)
        XCTAssertEqual(LockInOption.clampedMinutes(90), 90)
        XCTAssertEqual(LockInOption.clampedMinutes(999), 240)
    }

    func testSuggestedOptionFromEstimatedMinutes() {
        XCTAssertNil(LockInOption.suggestedOption(for: nil))
        XCTAssertNil(LockInOption.suggestedOption(for: 0))
        XCTAssertNil(LockInOption.suggestedOption(for: -10))

        let est25 = LockInOption.suggestedOption(for: 25)
        XCTAssertEqual(est25?.option, .minutes25)
        XCTAssertEqual(est25?.customMinutes, 25)

        let est50 = LockInOption.suggestedOption(for: 50)
        XCTAssertEqual(est50?.option, .minutes50)
        XCTAssertEqual(est50?.customMinutes, 50)

        let est90 = LockInOption.suggestedOption(for: 90)
        XCTAssertEqual(est90?.option, .minutes90)
        XCTAssertEqual(est90?.customMinutes, 90)

        let est40 = LockInOption.suggestedOption(for: 40)
        XCTAssertEqual(est40?.option, .custom)
        XCTAssertEqual(est40?.customMinutes, 40)

        let estLow = LockInOption.suggestedOption(for: 2)
        XCTAssertEqual(estLow?.option, .custom)
        XCTAssertEqual(estLow?.customMinutes, 5) // clamped to floor

        let estHigh = LockInOption.suggestedOption(for: 300)
        XCTAssertEqual(estHigh?.option, .custom)
        XCTAssertEqual(estHigh?.customMinutes, 240) // clamped to ceiling
    }
}
