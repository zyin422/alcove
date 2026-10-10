import XCTest
@testable import Accountabilibrosis

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

    func testCustomUsesTheStepperValueClampedToItsRange() {
        XCTAssertEqual(LockInOption.customRange, 5...240)
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 45), .goal(minutes: 45))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 1), .goal(minutes: 5))
        XCTAssertEqual(LockInOption.custom.mode(customMinutes: 500), .goal(minutes: 240))
    }
}
