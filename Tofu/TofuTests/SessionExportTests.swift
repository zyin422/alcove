import XCTest
@testable import Tofu

final class SessionExportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ name: String, offset: TimeInterval = 0, minutes: Double = 25,
                         mode: SessionMode = .goal(minutes: 25), outcome: SessionOutcome = .completed,
                         ended: Bool = true, demo: Bool = false) -> Session {
        let begin = start.addingTimeInterval(offset)
        return Session(subjectID: UUID(), subjectName: name, mode: mode, start: begin,
                       end: ended ? begin.addingTimeInterval(minutes * 60) : nil,
                       blockedAttempts: 2, closedTabs: 1, outcome: ended ? outcome : nil, isDemo: demo)
    }

    func testExportableSkipsUnfinishedAndDemoAndSortsOldestFirst() {
        let later = session("B", offset: 3600)
        let earlier = session("A")
        let sessions = [later, session("open", ended: false), session("demo", demo: true), earlier]
        XCTAssertEqual(SessionExport.exportable(sessions).map(\.subjectName), ["A", "B"])
    }

    func testCSVHasHeaderAndOneRowPerSession() {
        let csv = SessionExport.csv([session("CS128", minutes: 25), session("math", offset: 60, mode: .open, outcome: .bailed)])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.first.map(String.init), SessionExport.csvHeader)
        XCTAssertEqual(lines.count, 4)   // header, 2 rows, trailing newline
        XCTAssertTrue(lines[1].hasPrefix("CS128,"))
        XCTAssertTrue(lines[1].hasSuffix(",25.0,goal,25,completed,2,1"))
        XCTAssertTrue(lines[2].hasSuffix(",open,,bailed,2,1"))
    }

    func testCSVEscapesCommasQuotesAndNewlines() {
        XCTAssertEqual(SessionExport.escape("plain"), "plain")
        XCTAssertEqual(SessionExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(SessionExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(SessionExport.escape("two\nlines"), "\"two\nlines\"")
    }

    func testEmptyCSVIsJustTheHeader() {
        XCTAssertEqual(SessionExport.csv([]), SessionExport.csvHeader + "\n")
    }

    func testJSONHasTheSameFields() throws {
        let data = try SessionExport.json([session("CS128", minutes: 12.34)])
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record["subject"] as? String, "CS128")
        XCTAssertEqual(record["minutes"] as? Double, 12.3)
        XCTAssertEqual(record["mode"] as? String, "goal")
        XCTAssertEqual(record["goalMinutes"] as? Int, 25)
        XCTAssertEqual(record["outcome"] as? String, "completed")
        XCTAssertEqual(record["blockedAttempts"] as? Int, 2)
        XCTAssertNotNil(record["start"] as? String)
    }

    func testFileNameUsesTheLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        XCTAssertEqual(SessionExport.fileName(format: .csv, now: date, calendar: calendar), "tofu-sessions-2026-03-07.csv")
        XCTAssertEqual(SessionExport.fileName(format: .json, now: date, calendar: calendar), "tofu-sessions-2026-03-07.json")
    }
}
