import XCTest
@testable import Tofu

final class GoogleEventFormatTests: XCTestCase {
    private func timed(_ startISO: String, _ endISO: String) -> GoogleEvent {
        GoogleEvent(id: "e", summary: "X",
                    start: GoogleEventTime(dateTime: startISO, date: nil),
                    end: GoogleEventTime(dateTime: endISO, date: nil))
    }

    func testTimedEventLabelShowsStartAndEnd() {
        let event = timed("2026-10-15T09:00:00-05:00", "2026-10-15T09:50:00-05:00")
        let label = GoogleEventFormat.timeLabel(event)
        XCTAssertTrue(label.contains("–"), "label joins start and end: \(label)")
        XCTAssertFalse(label.isEmpty)
    }

    func testAllDayEventLabelAndSort() {
        let allDay = GoogleEvent(id: "e2", summary: "Career fair",
                                 start: GoogleEventTime(dateTime: nil, date: "2026-10-15"),
                                 end: GoogleEventTime(dateTime: nil, date: "2026-10-16"))
        XCTAssertEqual(GoogleEventFormat.timeLabel(allDay), "All day")
        let sortKey = GoogleEventFormat.sortKey(allDay, calendar: .current)
        let timedKey = GoogleEventFormat.sortKey(timed("2026-10-15T09:00:00-05:00", "2026-10-15T10:00:00-05:00"),
                                                 calendar: .current)
        XCTAssertLessThanOrEqual(sortKey, timedKey, "all-day events sort to the top")
    }
}
