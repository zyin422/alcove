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

    func testExportMarkdownFormatting() {
        let thoughts = ["Review lecture slides", "Fix segmentation fault in parser"]
        let markdown = ThoughtParkingEngine.exportMarkdown(
            thoughts: thoughts,
            subjectName: "Operating Systems",
            dateString: "2026-11-24"
        )

        XCTAssertTrue(markdown.contains("### Parked Thoughts - Operating Systems (2026-11-24)"))
        XCTAssertTrue(markdown.contains("- [ ] Review lecture slides"))
        XCTAssertTrue(markdown.contains("- [ ] Fix segmentation fault in parser"))
    }

    func testExportMarkdownWithEmptyList() {
        let markdown = ThoughtParkingEngine.exportMarkdown(thoughts: [], subjectName: "Math", dateString: "2026-11-24")
        XCTAssertEqual(markdown, "")
    }

    func testFormatAsPriorities() {
        let subID = UUID()
        let thoughts = ["Order textbooks", "Schedule team meeting"]
        let priorities = ThoughtParkingEngine.formatAsPriorities(thoughts: thoughts, subjectID: subID)

        XCTAssertEqual(priorities.count, 2)
        XCTAssertEqual(priorities[0].title, "Order textbooks")
        XCTAssertEqual(priorities[0].subjectID, subID)
        XCTAssertFalse(priorities[0].isDone)
        XCTAssertEqual(priorities[1].title, "Schedule team meeting")
    }

    func testPromoteThoughtToPriorityWithParsedDetails() {
        let mathID = UUID()
        let mathSub = Subject(id: mathID, name: "Math", details: "Calculus")
        let csID = UUID()
        let csSub = Subject(id: csID, name: "CS128", details: "C++")

        // Thought with time and duration matching a subject
        let thought1 = "9am CS128 lab 45m"
        let priority1 = ThoughtParkingEngine.promoteThoughtToPriority(thought: thought1, subjects: [mathSub, csSub], fallbackSubjectID: mathID)

        XCTAssertEqual(priority1.title, "CS128 lab")
        XCTAssertEqual(priority1.subjectID, csID)
        XCTAssertEqual(priority1.estimatedMinutes, 45)
        XCTAssertEqual(priority1.scheduledMinutesFromMidnight, 9 * 60)
        XCTAssertFalse(priority1.isDone)

        // Thought without subject matching -> uses fallbackSubjectID
        let thought2 = "Draft lab report 30m"
        let priority2 = ThoughtParkingEngine.promoteThoughtToPriority(thought: thought2, subjects: [mathSub, csSub], fallbackSubjectID: mathID)

        XCTAssertEqual(priority2.title, "Draft lab report")
        XCTAssertEqual(priority2.subjectID, mathID)
        XCTAssertEqual(priority2.estimatedMinutes, 30)
        XCTAssertNil(priority2.scheduledMinutesFromMidnight)
    }

    func testPromoteThoughtToPriorityWithHashtagSubjectRouting() {
        let mathID = UUID()
        let mathSub = Subject(id: mathID, name: "Math", details: "Calculus")
        let mlID = UUID()
        let mlSub = Subject(id: mlID, name: "Machine Learning", details: "Neural nets")

        // Thought starting with hashtag
        let thought1 = "#math Solve problem set 4 (50m)"
        let p1 = ThoughtParkingEngine.promoteThoughtToPriority(thought: thought1, subjects: [mathSub, mlSub])
        XCTAssertEqual(p1.title, "Solve problem set 4")
        XCTAssertEqual(p1.subjectID, mathID)
        XCTAssertEqual(p1.estimatedMinutes, 50)

        // Thought with hyphenated hashtag matching multi-word subject
        let thought2 = "Implement backprop algorithm #machine-learning 45m"
        let p2 = ThoughtParkingEngine.promoteThoughtToPriority(thought: thought2, subjects: [mathSub, mlSub])
        XCTAssertEqual(p2.title, "Implement backprop algorithm")
        XCTAssertEqual(p2.subjectID, mlID)
        XCTAssertEqual(p2.estimatedMinutes, 45)

        // Hashtag that doesn't match any subject falls back to fallbackSubjectID
        let thought3 = "#random Buy groceries"
        let p3 = ThoughtParkingEngine.promoteThoughtToPriority(thought: thought3, subjects: [mathSub, mlSub], fallbackSubjectID: mathID)
        XCTAssertEqual(p3.title, "#random Buy groceries")
        XCTAssertEqual(p3.subjectID, mathID)
    }
}
