import XCTest
@testable import Tofu

private func task(_ id: String, _ title: String, done: Bool = false, completed: String? = nil) -> GoogleTask {
    GoogleTask(id: id, title: title, status: done ? "completed" : "needsAction", completed: completed, due: nil)
}

final class GoogleTaskMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)   // fixed instant

    // MARK: apply (pull; remote wins)

    func testRemoteTasksBecomePriorities() {
        let (priorities, toInsert) = GoogleTaskMerge.apply(remote: [task("t1", "Read"), task("t2", "PS4")], to: [], now: now)
        XCTAssertEqual(priorities.map(\.title), ["Read", "PS4"])
        XCTAssertEqual(priorities.map(\.googleTaskID), ["t1", "t2"])
        XCTAssertTrue(toInsert.isEmpty)
    }

    func testLinkedLocalKeepsIdentityAndSubjectButFollowsRemote() {
        let subjectID = UUID()
        var linked = Priority(title: "Old title", subjectID: subjectID)
        linked.googleTaskID = "t1"
        let (priorities, _) = GoogleTaskMerge.apply(remote: [task("t1", "New title", done: true,
                                                                  completed: GoogleEventTime.rfc3339.string(from: now))],
                                                    to: [linked], now: now)
        XCTAssertEqual(priorities.count, 1)
        XCTAssertEqual(priorities[0].id, linked.id, "UUID survives so UI selection/links hold")
        XCTAssertEqual(priorities[0].subjectID, subjectID)
        XCTAssertEqual(priorities[0].title, "New title")
        XCTAssertTrue(priorities[0].isDone)
    }

    func testTaskCompletedBeforeTodayIsIgnored() {
        let yesterday = GoogleEventTime.rfc3339.string(from: now.addingTimeInterval(-86_400 * 2))
        let (priorities, _) = GoogleTaskMerge.apply(remote: [task("t1", "Done long ago", done: true, completed: yesterday)],
                                                    to: [], now: now)
        XCTAssertTrue(priorities.isEmpty)
    }

    func testTaskCompletedTodayShowsAsDone() {
        let completed = GoogleEventTime.rfc3339.string(from: now.addingTimeInterval(-60))
        let (priorities, _) = GoogleTaskMerge.apply(remote: [task("t1", "Just finished", done: true, completed: completed)],
                                                    to: [], now: now)
        XCTAssertEqual(priorities.map(\.isDone), [true])
    }

    func testUnlinkedLocalSurvivesAndIsQueuedForInsert() {
        let local = Priority(title: "Added in Tofu")
        let (priorities, toInsert) = GoogleTaskMerge.apply(remote: [task("t1", "Remote")], to: [local], now: now)
        XCTAssertEqual(priorities.map(\.title), ["Added in Tofu", "Remote"], "locals keep their place, new remotes append")
        XCTAssertEqual(toInsert.map(\.id), [local.id])
    }

    func testLinkedLocalGoneFromRemoteIsDroppedUnlessDone() {
        var gone = Priority(title: "Deleted in Google"); gone.googleTaskID = "t-gone"
        var keptDone = Priority(title: "Finished earlier", isDone: true); keptDone.googleTaskID = "t-done-gone"
        let (priorities, _) = GoogleTaskMerge.apply(remote: [], to: [gone, keptDone], now: now)
        XCTAssertEqual(priorities.map(\.title), ["Finished earlier"], "done ones stay as the day's record")
    }

    func testUntitledRemoteTaskGetsPlaceholder() {
        let (priorities, _) = GoogleTaskMerge.apply(remote: [GoogleTask(id: "t1", title: nil, status: "needsAction",
                                                                        completed: nil, due: nil)], to: [], now: now)
        XCTAssertEqual(priorities.map(\.title), ["(untitled)"])
    }

    // MARK: diff (local push)

    func testDiffFindsInsertCompleteReopenDeleteRetitle() {
        var done = Priority(title: "A"); done.googleTaskID = "tA"
        var reopened = Priority(title: "B", isDone: true); reopened.googleTaskID = "tB"
        var deleted = Priority(title: "C"); deleted.googleTaskID = "tC"
        var renamed = Priority(title: "D"); renamed.googleTaskID = "tD"
        let old = [done, reopened, deleted, renamed]
        var newDone = done; newDone.isDone = true
        var newReopened = reopened; newReopened.isDone = false
        var newRenamed = renamed; newRenamed.title = "D v2"
        let added = Priority(title: "E")
        let diff = GoogleTaskMerge.diff(from: old, to: [newDone, newReopened, newRenamed, added])
        XCTAssertEqual(diff.inserts.map(\.id), [added.id])
        XCTAssertEqual(diff.completes, ["tA"])
        XCTAssertEqual(diff.reopens, ["tB"])
        XCTAssertEqual(diff.deletes, ["tC"])
        XCTAssertEqual(diff.retitles, [Retitle(id: "tD", title: "D v2")])
    }

    func testDiffOfIdenticalPlansIsEmpty() {
        var linked = Priority(title: "A"); linked.googleTaskID = "tA"
        XCTAssertTrue(GoogleTaskMerge.diff(from: [linked], to: [linked]).isEmpty)
    }

    func testDiffIgnoresUnlinkedRemovals() {
        let unlinked = Priority(title: "Never synced")
        XCTAssertTrue(GoogleTaskMerge.diff(from: [unlinked], to: []).isEmpty,
                      "nothing to delete in Google for a priority that was never there")
    }
}
