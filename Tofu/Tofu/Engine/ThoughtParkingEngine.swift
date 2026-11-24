import Foundation

/// Pure engine for exporting and triaging parked thoughts captured during focus blocks.
enum ThoughtParkingEngine {
    /// Formats a list of parked thoughts into clean Markdown checklist syntax.
    static func exportMarkdown(thoughts: [String], subjectName: String, dateString: String) -> String {
        let cleaned = thoughts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("### Parked Thoughts - \(subjectName) (\(dateString))")
        for thought in cleaned {
            lines.append("- [ ] \(thought)")
        }
        return lines.joined(separator: "\n")
    }

    /// Converts raw parked thoughts into structured priorities for today's or tomorrow's plan.
    static func formatAsPriorities(thoughts: [String], subjectID: UUID? = nil) -> [Priority] {
        thoughts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Priority(title: $0, subjectID: subjectID) }
    }

    /// Promotes a single parked thought into a scheduled priority, parsing estimated time and matching subjects.
    static func promoteThoughtToPriority(thought: String, subjects: [Subject] = [], fallbackSubjectID: UUID? = nil) -> Priority {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        let (title, estimatedMinutes, scheduledMinutes) = DayPlanner.parsePriorityDetails(from: trimmed)
        let matchedSubjectID = DayPlanner.matchSubject(title, subjects: subjects) ?? fallbackSubjectID
        return Priority(
            title: title.isEmpty ? trimmed : title,
            subjectID: matchedSubjectID,
            estimatedMinutes: estimatedMinutes,
            scheduledMinutesFromMidnight: scheduledMinutes
        )
    }
}
