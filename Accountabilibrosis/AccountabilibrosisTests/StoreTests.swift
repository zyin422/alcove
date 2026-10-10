import XCTest
@testable import Accountabilibrosis

final class StoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)   // whole seconds: ISO8601 keeps them exactly

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("store.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleData() -> StoreData {
        let subjectID = UUID()
        let subject = Subject(id: subjectID, name: "CS128", preset: .thirds,
                              sites: ["https://cs128.org", "piazza.com/class/x"],
                              allowedApps: [AllowedApp(bundleID: "com.apple.Notes", name: "Notes")],
                              extraDomains: ["stackoverflow.com"], createdAt: t0)
        let finished = Session(subjectID: subjectID, subjectName: "CS128", mode: .goal(minutes: 25),
                               start: t0, end: t0.addingTimeInterval(1500),
                               lastHeartbeat: t0.addingTimeInterval(1490), blockedAttempts: 3, closedTabs: 2,
                               outcome: .completed)
        let open = Session(subjectID: subjectID, subjectName: "CS128", mode: .open,
                           start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(4200),
                           lastHeartbeat: t0.addingTimeInterval(4200), outcome: .bailed, isDemo: true)
        let settings = AppSettings(displayName: "Alex", discordEnabled: true,
                                   giveUpTemplate: "I quit {subject}", channelCache: ["111": "222"])
        return StoreData(version: 1, subjects: [subject], sessions: [finished, open], settings: settings)
    }

    private func backupFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("store.corrupt-") && $0.hasSuffix(".json") }
            .sorted()
    }

    func testMissingFileLoadsEmptyWithoutWarning() {
        let result = Store(fileURL: fileURL).load()
        XCTAssertEqual(result.data, StoreData.empty)
        XCTAssertNil(result.warning)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = Store(fileURL: fileURL)
        let data = sampleData()
        try store.save(data)
        let result = store.load()
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.data, data)
    }

    func testSaveWritesPrettyPrintedJSONWithISODates() throws {
        try Store(fileURL: fileURL).save(sampleData())
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\" : 1"), text)
        XCTAssertTrue(text.contains("\"2025-10-09T08:53:20Z\""), text)
        XCTAssertFalse(text.contains("bot-token"))
    }

    func testSaveCreatesMissingDirectory() throws {
        let nested = directory.appendingPathComponent("a/b/store.json")
        try Store(fileURL: nested).save(sampleData())
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testCorruptFileIsBackedUpAndLoadsEmptyWithWarning() throws {
        try Data("not json {".utf8).write(to: fileURL)
        let result = Store(fileURL: fileURL).load()
        XCTAssertEqual(result.data, StoreData.empty)
        let warning = try XCTUnwrap(result.warning)
        XCTAssertTrue(warning.contains("store.corrupt-"), warning)
        let backups = try backupFiles()
        XCTAssertEqual(backups.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let backupURL = directory.appendingPathComponent(backups[0])
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "not json {")
    }

    func testSecondCorruptFileDoesNotOverwriteFirstBackup() throws {
        let store = Store(fileURL: fileURL)
        try Data("first".utf8).write(to: fileURL)
        _ = store.load()
        try Data("second".utf8).write(to: fileURL)
        _ = store.load()
        XCTAssertEqual(try backupFiles().count, 2)
    }

    func testFinalizeInterruptedClosesOpenSessionsAtLastHeartbeat() {
        var data = sampleData()
        let finished = data.sessions[0]
        let active = Session(subjectID: UUID(), subjectName: "MATH241", mode: .open, start: t0,
                             lastHeartbeat: t0.addingTimeInterval(600), blockedAttempts: 4)
        data.sessions.append(active)

        let result = Store.finalizeInterrupted(data)

        XCTAssertEqual(result.sessions[0], finished)
        XCTAssertEqual(result.sessions[1], data.sessions[1])
        let closed = result.sessions[2]
        XCTAssertEqual(closed.end, t0.addingTimeInterval(600))
        XCTAssertEqual(closed.outcome, .interrupted)
        XCTAssertEqual(closed.duration, 600)
        XCTAssertEqual(closed.blockedAttempts, 4)
        XCTAssertEqual(closed.id, active.id)
    }

    func testLoadAppliesFinalizeInterrupted() throws {
        var data = sampleData()
        data.sessions.append(Session(subjectID: UUID(), subjectName: "MATH241", mode: .goal(minutes: 50),
                                     start: t0, lastHeartbeat: t0.addingTimeInterval(1200)))
        let store = Store(fileURL: fileURL)
        try store.save(data)

        let loaded = store.load().data

        XCTAssertEqual(loaded.sessions.count, 3)
        XCTAssertEqual(loaded.sessions[2].end, t0.addingTimeInterval(1200))
        XCTAssertEqual(loaded.sessions[2].outcome, .interrupted)
        XCTAssertEqual(Array(loaded.sessions.prefix(2)), Array(data.sessions.prefix(2)))
    }

    func testDefaultURLIsInApplicationSupport() {
        let url = Store.defaultURL()
        XCTAssertTrue(url.path.hasSuffix("Library/Application Support/Accountabilibrosis/store.json"), url.path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path,
                                                     isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
