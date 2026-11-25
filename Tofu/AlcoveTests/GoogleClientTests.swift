import XCTest
@testable import Alcove

final class GoogleClientTests: XCTestCase {
    private func makeClient(_ transport: MockTransport) -> GoogleClient {
        GoogleClient(tokenProvider: { _ in "at-1" }, transport: transport)
    }

    func testListTasksRequestsDefaultListWithCompletedAndHidden() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"items": [{"id": "t1", "title": "Read", "status": "needsAction"}]}"#)) }
        let tasks = try await makeClient(transport).listTasks()
        XCTAssertEqual(tasks, [GoogleTask(id: "t1", title: "Read", status: "needsAction", completed: nil, due: nil)])
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/tasks/v1/lists/@default/tasks")
        XCTAssertTrue(url.query?.contains("showCompleted=true") ?? false)
        XCTAssertTrue(url.query?.contains("showHidden=true") ?? false, "completed tasks are hidden without it")
        XCTAssertTrue(url.query?.contains("maxResults=100") ?? false)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer at-1")
    }

    func testListTasksFollowsNextPageToken() async throws {
        let transport = MockTransport { request in
            if request.url?.query?.contains("pageToken=p2") ?? false {
                return (200, MockTransport.json(#"{"items": [{"id": "t2", "status": "needsAction"}]}"#))
            }
            return (200, MockTransport.json(
                #"{"items": [{"id": "t1", "status": "needsAction"}], "nextPageToken": "p2"}"#))
        }
        let tasks = try await makeClient(transport).listTasks()
        XCTAssertEqual(tasks.map(\.id), ["t1", "t2"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testListTasksWithNoItemsKeyReturnsEmpty() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json("{}")) }   // Google omits "items" when empty
        let tasks = try await makeClient(transport).listTasks()
        XCTAssertEqual(tasks, [])
    }

    func testInsertTaskPostsTitleAndDue() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"id": "t9", "title": "PS4", "status": "needsAction"}"#)) }
        let task = try await makeClient(transport).insertTask(title: "PS4", due: "2026-10-15T00:00:00.000Z")
        XCTAssertEqual(task.id, "t9")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/tasks/v1/lists/@default/tasks")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["title": "PS4", "due": "2026-10-15T00:00:00.000Z"])
    }

    func testPatchTaskSendsOnlyGivenFields() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "t1", "status": "completed"}"#)) }
        _ = try await makeClient(transport).patchTask(id: "t1", title: nil, status: "completed")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/tasks/v1/lists/@default/tasks/t1")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["status": "completed"])
    }

    func testDeleteTask() async throws {
        let transport = MockTransport { _ in (204, Data()) }
        try await makeClient(transport).deleteTask(id: "t1")
        XCTAssertEqual(transport.log, ["DELETE /tasks/v1/lists/@default/tasks/t1"])
    }

    func testListCalendarsDecodesSelected() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"items": [{"id": "primary-id", "summary": "Me", "selected": true}, {"id": "alcove-id", "summary": "Alcove"}]}"#)) }
        let calendars = try await makeClient(transport).listCalendars()
        XCTAssertEqual(calendars.count, 2)
        XCTAssertEqual(calendars[0].selected, true)
        XCTAssertEqual(transport.requests.first?.url?.path, "/calendar/v3/users/me/calendarList")
    }

    func testInsertCalendar() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "cal-9", "summary": "Alcove"}"#)) }
        let calendar = try await makeClient(transport).insertCalendar(summary: "Alcove")
        XCTAssertEqual(calendar.id, "cal-9")
        XCTAssertEqual(transport.log, ["POST /calendar/v3/calendars"])
    }

    func testInsertEventBodyAndPath() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(#"{"id": "ev-1"}"#)) }
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        try await makeClient(transport).insertEvent(calendarID: "cal-9", summary: "Focus: CS128",
                                                    description: "Goal 50 min", start: start,
                                                    end: start.addingTimeInterval(3000))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/calendar/v3/calendars/cal-9/events")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["summary"] as? String, "Focus: CS128")
        let startField = try XCTUnwrap(body["start"] as? [String: String])
        XCTAssertNotNil(startField["dateTime"])
    }

    func testListEventsWindowAndDecoding() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json(
            #"{"items": [{"id": "e1", "summary": "Lecture", "start": {"dateTime": "2026-10-15T09:00:00-05:00"}, "end": {"dateTime": "2026-10-15T09:50:00-05:00"}}, {"id": "e2", "summary": "Fair", "start": {"date": "2026-10-15"}, "end": {"date": "2026-10-16"}}]}"#)) }
        let events = try await makeClient(transport).listEvents(calendarID: "a@b.com", from: Date(), to: Date())
        XCTAssertEqual(events.count, 2)
        XCTAssertNotNil(events[0].start.parsed)
        XCTAssertNil(events[1].start.parsed, "all-day events have no dateTime")
        XCTAssertEqual(events[1].start.date, "2026-10-15")
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertTrue(url.query?.contains("singleEvents=true") ?? false)
        XCTAssertTrue(url.query?.contains("timeMin=") ?? false)
        XCTAssertTrue(url.query?.contains("timeMax=") ?? false)
    }

    func testUnauthorizedForcesOneRefreshAndRetries() async throws {
        var tokens = ["at-old", "at-new"]
        var provided: [Bool] = []
        let transport = MockTransport { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer at-new"
                ? (200, MockTransport.json("{}")) : (401, Data())
        }
        let client = GoogleClient(tokenProvider: { force in provided.append(force); return tokens.removeFirst() },
                                  transport: transport)
        _ = try await client.listTasks()
        XCTAssertEqual(provided, [false, true], "the retry must force a refresh")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSecondUnauthorizedThrowsHTTP401() async {
        let transport = MockTransport { _ in (401, Data()) }
        let client = GoogleClient(tokenProvider: { _ in "at-1" }, transport: transport)
        do { _ = try await client.listTasks(); XCTFail("expected http(401)") }
        catch let error as GoogleError { XCTAssertEqual(error, .http(401)) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(transport.requests.count, 2, "exactly one retry")
    }

    func testCalendarIDIsPercentEncodedInPath() async throws {
        let transport = MockTransport { _ in (200, MockTransport.json("{}")) }
        _ = try await makeClient(transport).listEvents(calendarID: "en.usa#holiday@group.v.calendar.google.com",
                                                       from: Date(), to: Date())
        let path = transport.requests.first?.url?.absoluteString ?? ""
        XCTAssertTrue(path.contains("%23holiday"), "the # in calendar ids must be encoded, got \(path)")
    }

    private struct ThrowingTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
    }

    private func assertThrows(_ expected: GoogleError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let error as GoogleError { XCTAssertEqual(error, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    func testTransportFailureMapsToTransportError() async {
        let client = GoogleClient(tokenProvider: { _ in "at-1" }, transport: ThrowingTransport())
        do { _ = try await client.listTasks(); XCTFail("expected transport error") }
        catch let error as GoogleError {
            if case .transport = error {} else { XCTFail("expected .transport, got \(error)") }
        } catch { XCTFail("unexpected \(error)") }
    }

    func testNon401ErrorStatusMapsToHTTPError() async {
        let transport = MockTransport { _ in (500, Data()) }
        await assertThrows(.http(500)) { _ = try await makeClient(transport).listTasks() }
        XCTAssertEqual(transport.requests.count, 1, "only 401 retries")
    }

    func testMalformedSuccessBodyMapsToDecoding() async {
        let transport = MockTransport { _ in (200, MockTransport.json("not json")) }
        await assertThrows(.decoding) { _ = try await makeClient(transport).listTasks() }
    }

    func testPageTokenIsPercentEncoded() async throws {
        let transport = MockTransport { request in
            request.url?.query?.contains("pageToken=") ?? false
                ? (200, MockTransport.json("{}"))
                : (200, MockTransport.json(#"{"items": [], "nextPageToken": "a+b&c"}"#))
        }
        _ = try await makeClient(transport).listTasks()
        XCTAssertTrue(transport.requests[1].url?.absoluteString.contains("pageToken=a%2Bb%26c") ?? false)
    }
}
