import XCTest
@testable import Tofu

final class ThoughtParkingTests: XCTestCase {
    @MainActor
    func testAddAndRemoveParkedThoughtsInSessionEngine() async {
        let harness = EngineHarness()
        let subject = Subject(name: "Algorithms", details: "Graph theory")
        await harness.engine.start(subject: subject, mode: .open, displayName: "Tester")

        XCTAssertEqual(harness.engine.parkedThoughts.count, 0)

        harness.engine.addParkedThought("Buy coffee")
        harness.engine.addParkedThought("Check email from professor")
        XCTAssertEqual(harness.engine.parkedThoughts, ["Buy coffee", "Check email from professor"])

        // Trimming and whitespace suppression
        harness.engine.addParkedThought("   ")
        harness.engine.addParkedThought("  Research Dijkstra optimization  ")
        XCTAssertEqual(harness.engine.parkedThoughts.count, 3)
        XCTAssertEqual(harness.engine.parkedThoughts[2], "Research Dijkstra optimization")

        // Remove thought at index 1
        harness.engine.removeParkedThought(at: 1)
        XCTAssertEqual(harness.engine.parkedThoughts, ["Buy coffee", "Research Dijkstra optimization"])

        // Out of bounds removal does not crash
        harness.engine.removeParkedThought(at: 99)
        harness.engine.removeParkedThought(at: -1)
        XCTAssertEqual(harness.engine.parkedThoughts.count, 2)
    }

    func testSessionParkedThoughtsCoding() throws {
        var session = Session(subjectID: UUID(), subjectName: "CS225", mode: .open, start: Date())
        session.parkedThoughts = ["[Task] Fix memory leak", "[Idea] Vector acceleration"]

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        XCTAssertEqual(decoded.parkedThoughts, ["[Task] Fix memory leak", "[Idea] Vector acceleration"])
    }
}
