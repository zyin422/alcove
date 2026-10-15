import Foundation

struct Retitle: Equatable { var id: String; var title: String }

/// What changed locally between two versions of today's plan, in Google terms.
struct PlanDiff: Equatable {
    var inserts: [Priority] = []     // new local priorities with no googleTaskID yet
    var completes: [String] = []     // googleTaskIDs whose priority flipped to done
    var reopens: [String] = []       // flipped back to not done
    var deletes: [String] = []       // linked priorities that were removed
    var retitles: [Retitle] = []
    var isEmpty: Bool { inserts.isEmpty && completes.isEmpty && reopens.isEmpty && deletes.isEmpty && retitles.isEmpty }
}

enum GoogleTaskMerge {
    private static let untitled = "(untitled)"

    /// Remote wins (spec §3). Returns today's new priority list and the local-only ones to insert.
    static func apply(remote: [GoogleTask], to local: [Priority], now: Date = Date(),
                      calendar: Calendar = .current) -> (priorities: [Priority], toInsert: [Priority]) {
        let today = DayKey.key(for: now, calendar: calendar)
        let kept = remote.filter { task in
            if !task.isDone { return true }
            guard let stamp = task.completed, let date = GoogleEventTime.rfc3339.date(from: stamp) else { return false }
            return DayKey.key(for: date, calendar: calendar) == today
        }
        let keptByID = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var result: [Priority] = []
        var toInsert: [Priority] = []
        var matched = Set<String>()
        for priority in local {
            guard let linkID = priority.googleTaskID else {
                result.append(priority)
                toInsert.append(priority)
                continue
            }
            if let task = keptByID[linkID] {
                var updated = priority
                updated.title = task.title ?? untitled
                updated.isDone = task.isDone
                result.append(updated)
                matched.insert(linkID)
            } else if priority.isDone {
                result.append(priority)
            }
        }
        for task in kept where !matched.contains(task.id) {
            result.append(Priority(title: task.title ?? untitled, isDone: task.isDone, googleTaskID: task.id))
            matched.insert(task.id)
        }
        return (result, toInsert)
    }

    /// Google-side changes implied by going from `old` to `new`, matched by priority UUID.
    static func diff(from old: [Priority], to new: [Priority]) -> PlanDiff {
        var plan = PlanDiff()
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIDs = Set(new.map(\.id))

        for priority in new {
            guard let before = oldByID[priority.id] else {
                if priority.googleTaskID == nil { plan.inserts.append(priority) }
                continue
            }
            guard let linkID = priority.googleTaskID else { continue }
            if !before.isDone && priority.isDone { plan.completes.append(linkID) }
            if before.isDone && !priority.isDone { plan.reopens.append(linkID) }
            if before.title != priority.title { plan.retitles.append(Retitle(id: linkID, title: priority.title)) }
        }
        for priority in old where !newIDs.contains(priority.id) {
            if let linkID = priority.googleTaskID { plan.deletes.append(linkID) }
        }
        return plan
    }
}
