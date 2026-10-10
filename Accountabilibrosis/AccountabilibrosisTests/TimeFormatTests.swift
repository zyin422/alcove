import XCTest
@testable import Accountabilibrosis

final class TimeFormatTests: XCTestCase {
    func testShortFloorsToMinutes() {
        XCTAssertEqual(TimeFormat.short(0), "0m")
        XCTAssertEqual(TimeFormat.short(59), "0m")
        XCTAssertEqual(TimeFormat.short(59 * 60 + 59), "59m")
        XCTAssertEqual(TimeFormat.short(3600), "1h 0m")
        XCTAssertEqual(TimeFormat.short(4800), "1h 20m")
        XCTAssertEqual(TimeFormat.short(10 * 3600 + 5 * 60 + 30), "10h 5m")
    }

    func testShortNegativeAndNonFiniteAreZero() {
        XCTAssertEqual(TimeFormat.short(-5), "0m")
        XCTAssertEqual(TimeFormat.short(.nan), "0m")
        XCTAssertEqual(TimeFormat.short(-.infinity), "0m")
    }

    func testClockUnderAnHourIsMinutesSeconds() {
        XCTAssertEqual(TimeFormat.clock(0), "00:00")
        XCTAssertEqual(TimeFormat.clock(5.9), "00:05")
        XCTAssertEqual(TimeFormat.clock(65), "01:05")
        XCTAssertEqual(TimeFormat.clock(3599), "59:59")
    }

    func testClockFromAnHourIncludesHours() {
        XCTAssertEqual(TimeFormat.clock(3600), "1:00:00")
        XCTAssertEqual(TimeFormat.clock(36000 + 61), "10:01:01")
    }

    func testClockNegativeAndNonFiniteAreZero() {
        XCTAssertEqual(TimeFormat.clock(-1), "00:00")
        XCTAssertEqual(TimeFormat.clock(.nan), "00:00")
    }

    func testClockFullAlwaysHasHoursMinutesSeconds() {
        XCTAssertEqual(TimeFormat.clockFull(0), "00:00:00")
        XCTAssertEqual(TimeFormat.clockFull(5.9), "00:00:05")
        XCTAssertEqual(TimeFormat.clockFull(65), "00:01:05")
        XCTAssertEqual(TimeFormat.clockFull(3599), "00:59:59")
        XCTAssertEqual(TimeFormat.clockFull(3600), "01:00:00")
        XCTAssertEqual(TimeFormat.clockFull(36000 + 61), "10:01:01")
    }

    func testClockFullGrowsPastTwoHourDigits() {
        XCTAssertEqual(TimeFormat.clockFull(360_000), "100:00:00")
    }

    func testClockFullNegativeAndNonFiniteAreZero() {
        XCTAssertEqual(TimeFormat.clockFull(-1), "00:00:00")
        XCTAssertEqual(TimeFormat.clockFull(.nan), "00:00:00")
        XCTAssertEqual(TimeFormat.clockFull(-.infinity), "00:00:00")
    }
}
