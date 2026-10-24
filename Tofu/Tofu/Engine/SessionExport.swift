import Foundation

/// Stats export (Stats › Export): every finished, non-demo session as CSV (one row each, for spreadsheets)
/// or JSON (the same fields, for scripts). Pure, so the formats are testable.
enum SessionExport {
    enum Format: String, CaseIterable, Identifiable {
        case csv, json
        var id: String { rawValue }
        var title: String { self == .csv ? "CSV" : "JSON" }
    }

    static let csvHeader = "subject,start,end,minutes,mode,goal_minutes,outcome,blocked_attempts,closed_tabs"

    /// Finished, non-demo sessions, oldest first.
    static func exportable(_ sessions: [Session]) -> [Session] {
        sessions.filter { $0.end != nil && !$0.isDemo }.sorted { $0.start < $1.start }
    }

    static func csv(_ sessions: [Session]) -> String {
        let rows = exportable(sessions).map { session in
            [escape(session.subjectName),
             timestamp(session.start),
             session.end.map(timestamp) ?? "",
             minutes(session.duration),
             session.mode.goalMinutes == nil ? "open" : "goal",
             session.mode.goalMinutes.map(String.init) ?? "",
             session.outcome?.rawValue ?? "",
             String(session.blockedAttempts),
             String(session.closedTabs)].joined(separator: ",")
        }
        return ([csvHeader] + rows).joined(separator: "\n") + "\n"
    }

    static func json(_ sessions: [Session]) throws -> Data {
        let records = exportable(sessions).map { session in
            Record(subject: session.subjectName, start: session.start, end: session.end ?? session.start,
                   minutes: (session.duration / 60 * 10).rounded() / 10,
                   mode: session.mode.goalMinutes == nil ? "open" : "goal",
                   goalMinutes: session.mode.goalMinutes, outcome: session.outcome?.rawValue,
                   blockedAttempts: session.blockedAttempts, closedTabs: session.closedTabs)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    static func data(_ sessions: [Session], format: Format) throws -> Data {
        switch format {
        case .csv: return Data(csv(sessions).utf8)
        case .json: return try json(sessions)
        }
    }

    /// "tofu-sessions-2026-10-24.csv"
    static func fileName(format: Format, now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "tofu-sessions-\(day).\(format.rawValue)"
    }

    private struct Record: Encodable {
        var subject: String
        var start: Date
        var end: Date
        var minutes: Double
        var mode: String
        var goalMinutes: Int?
        var outcome: String?
        var blockedAttempts: Int
        var closedTabs: Int
    }

    /// RFC 4180: quote a field holding a comma, quote or line break, doubling inner quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func minutes(_ duration: TimeInterval) -> String {
        String(format: "%.1f", duration / 60)
    }
}
