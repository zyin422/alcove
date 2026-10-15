import Foundation

enum GoogleError: Error, Equatable {
    case http(Int)
    case transport(String)
    case decoding
}

struct GoogleTask: Decodable, Equatable {
    let id: String
    var title: String?
    var status: String          // "needsAction" | "completed"
    var completed: String?      // RFC3339 timestamp, present when completed
    var due: String?
    var isDone: Bool { status == "completed" }
}

struct GoogleCalendarInfo: Decodable, Equatable {
    let id: String
    let summary: String?
    let selected: Bool?
}

struct GoogleEventTime: Decodable, Equatable {
    var dateTime: String?       // RFC3339 with offset, timed events
    var date: String?           // "2026-10-15", all-day events
    var parsed: Date? { dateTime.flatMap { GoogleEventTime.parseRFC3339($0) } }
    static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    static let rfc3339Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    /// Parses an RFC3339 stamp with or without fractional seconds.
    static func parseRFC3339(_ string: String) -> Date? {
        rfc3339.date(from: string) ?? rfc3339Fractional.date(from: string)
    }
}

struct GoogleEvent: Decodable, Equatable, Identifiable {
    let id: String
    var summary: String?
    var start: GoogleEventTime
    var end: GoogleEventTime
}

protocol GoogleAPI {
    func listTasks() async throws -> [GoogleTask]
    func insertTask(title: String, due: String?) async throws -> GoogleTask
    func patchTask(id: String, title: String?, status: String?) async throws -> GoogleTask
    func deleteTask(id: String) async throws
    func listCalendars() async throws -> [GoogleCalendarInfo]
    func insertCalendar(summary: String) async throws -> GoogleCalendarInfo
    func insertEvent(calendarID: String, summary: String, description: String, start: Date, end: Date) async throws
    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent]
}

/// Minimal REST client for the Google Tasks and Calendar APIs (spec §2 of the Google sync design).
final class GoogleClient: GoogleAPI {
    private static let tasksBase = "https://tasks.googleapis.com/tasks/v1"
    private static let calendarBase = "https://www.googleapis.com/calendar/v3"
    private let tokenProvider: (Bool) async throws -> String
    private let transport: HTTPTransport

    init(tokenProvider: @escaping (Bool) async throws -> String,
         transport: HTTPTransport = URLSessionTransport()) {
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    func listTasks() async throws -> [GoogleTask] {
        struct Page: Decodable { let items: [GoogleTask]?; let nextPageToken: String? }
        var all: [GoogleTask] = []
        var pageToken: String?
        repeat {
            var query = "showCompleted=true&showHidden=true&maxResults=100"
            if let pageToken { query += "&pageToken=\(encode(pageToken))" }
            let page: Page = try await get("\(Self.tasksBase)/lists/@default/tasks?\(query)")
            all.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    func insertTask(title: String, due: String?) async throws -> GoogleTask {
        var body: [String: String] = ["title": title]
        if let due { body["due"] = due }
        return try await send("POST", "\(Self.tasksBase)/lists/@default/tasks", json: body)
    }

    func patchTask(id: String, title: String?, status: String?) async throws -> GoogleTask {
        var body: [String: String] = [:]
        if let title { body["title"] = title }
        if let status { body["status"] = status }
        return try await send("PATCH", "\(Self.tasksBase)/lists/@default/tasks/\(id)", json: body)
    }

    func deleteTask(id: String) async throws {
        _ = try await raw("DELETE", "\(Self.tasksBase)/lists/@default/tasks/\(id)", body: nil)
    }

    func listCalendars() async throws -> [GoogleCalendarInfo] {
        struct Page: Decodable { let items: [GoogleCalendarInfo]? }
        let page: Page = try await get("\(Self.calendarBase)/users/me/calendarList")
        return page.items ?? []
    }

    func insertCalendar(summary: String) async throws -> GoogleCalendarInfo {
        try await send("POST", "\(Self.calendarBase)/calendars", json: ["summary": summary])
    }

    func insertEvent(calendarID: String, summary: String, description: String, start: Date, end: Date) async throws {
        struct Ignored: Decodable {}
        let body: [String: Any] = [
            "summary": summary,
            "description": description,
            "start": ["dateTime": GoogleEventTime.rfc3339.string(from: start)],
            "end": ["dateTime": GoogleEventTime.rfc3339.string(from: end)],
        ]
        let _: Ignored = try await send("POST", "\(Self.calendarBase)/calendars/\(encode(calendarID))/events", jsonAny: body)
    }

    func listEvents(calendarID: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        struct Page: Decodable { let items: [GoogleEvent]? }
        let timeMin = encode(GoogleEventTime.rfc3339.string(from: from))
        let timeMax = encode(GoogleEventTime.rfc3339.string(from: to))
        let page: Page = try await get("\(Self.calendarBase)/calendars/\(encode(calendarID))/events"
            + "?singleEvents=true&orderBy=startTime&maxResults=50&timeMin=\(timeMin)&timeMax=\(timeMax)")
        return page.items ?? []
    }

    // MARK: - Plumbing

    /// Percent-encodes calendar ids (they contain # and @) and RFC3339 timestamps (+ and :).
    private func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters:
            CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#+&=?"))) ?? string
    }

    private func get<T: Decodable>(_ url: String) async throws -> T {
        try await decode(raw("GET", url, body: nil))
    }

    private func send<T: Decodable>(_ method: String, _ url: String, json: [String: String]) async throws -> T {
        try await decode(raw(method, url, body: try JSONSerialization.data(withJSONObject: json)))
    }

    private func send<T: Decodable>(_ method: String, _ url: String, jsonAny: [String: Any]) async throws -> T {
        try await decode(raw(method, url, body: try JSONSerialization.data(withJSONObject: jsonAny)))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw GoogleError.decoding }
        return decoded
    }

    /// One request with a fresh access token; a 401 forces one token refresh and one retry.
    private func raw(_ method: String, _ url: String, body: Data?) async throws -> Data {
        var attempt = 0
        while true {
            let token = try await tokenProvider(attempt > 0)
            guard let requestURL = URL(string: url) else { throw GoogleError.transport("bad url") }
            var request = URLRequest(url: requestURL)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let data: Data
            let response: HTTPURLResponse
            do { (data, response) = try await transport.send(request) }
            catch { throw GoogleError.transport(error.localizedDescription) }
            if response.statusCode == 401, attempt == 0 { attempt += 1; continue }
            guard response.statusCode / 100 == 2 else { throw GoogleError.http(response.statusCode) }
            return data
        }
    }
}
