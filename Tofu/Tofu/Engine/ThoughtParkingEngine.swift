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

    /// Extracts a hashtag subject prefix or suffix from a thought (e.g. "#cs128 fix parser" or "fix parser #cs128"),
    /// matching against configured subjects (handling hyphens, spaces, and case-insensitivity), returning the cleaned title
    /// and matched subject ID.
    static func parseHashtagSubject(text: String, subjects: [Subject]) -> (cleanedTitle: String, subjectID: UUID?) {
        let pattern = #"(?i)(?:^|\s)#([a-zA-Z0-9_\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, nil)
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let tag = nsText.substring(with: match.range(at: 1)).lowercased().replacingOccurrences(of: "-", with: "")
            if let matched = subjects.first(where: {
                let subName = $0.name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
                return subName == tag
            }) {
                let fullMatchRange = match.range
                let cleaned = (nsText.replacingCharacters(in: fullMatchRange, with: "") as String)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (cleaned, matched.id)
            }
        }
        return (text, nil)
    }

    /// Promotes a single parked thought into a scheduled priority, parsing estimated time, scheduled time, hashtags, and matching subjects.
    static func promoteThoughtToPriority(thought: String, subjects: [Subject] = [], fallbackSubjectID: UUID? = nil) -> Priority {
        let (withoutTag, tagSubjectID) = parseHashtagSubject(text: thought, subjects: subjects)
        let trimmed = withoutTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let (title, estimatedMinutes, scheduledMinutes) = DayPlanner.parsePriorityDetails(from: trimmed)
        let matchedSubjectID = tagSubjectID ?? DayPlanner.matchSubject(title, subjects: subjects) ?? fallbackSubjectID
        let cleanedTitle = title.isEmpty ? trimmed : title
        let finalTitle = cleanedTitle.isEmpty ? thought.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedTitle
        let capitalized = finalTitle.prefix(1).uppercased() + finalTitle.dropFirst()
        return Priority(
            title: capitalized.isEmpty ? finalTitle : capitalized,
            subjectID: matchedSubjectID,
            estimatedMinutes: estimatedMinutes,
            scheduledMinutesFromMidnight: scheduledMinutes
        )
    }
}
