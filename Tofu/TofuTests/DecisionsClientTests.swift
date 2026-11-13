import XCTest
@testable import Tofu

private struct FailingTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

private func decisionsBody(_ probability: String) -> Data {
    MockTransport.json(#"""
    {"id": "dec_1", "model": "gpt-6-luna", "usage": {"input_tokens": 90},
     "answers": [{"type": "predicate", "name": "off_task", "probability": \#(probability)}]}
    """#)
}

final class DecisionsClientTests: XCTestCase {
    private let page = PageInfo(url: "https://www.youtube.com/watch?v=abc", title: "Lo-fi beats", description: nil, siteName: nil)

    private func makeClient(_ transport: HTTPTransport, timeout: TimeInterval = 8) -> DecisionsClient {
        DecisionsClient(apiKey: "sk-test", transport: transport, timeout: timeout)
    }

    // MARK: - Request

    func testRequestMethodURLHeadersAndTimeout() async throws {
        let transport = MockTransport { _ in (200, decisionsBody("0.92")) }
        _ = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128")

        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/decisions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 8)
    }

    func testCustomTimeoutIsApplied() async throws {
        let transport = MockTransport { _ in (200, decisionsBody("0.1")) }
        _ = try await makeClient(transport, timeout: 3).offTaskProbability(page: page, subject: "CS128")
        XCTAssertEqual(transport.requests.first?.timeoutInterval, 3)
    }

    func testRequestBodyCarriesModelInputAndPredicateQuestion() async throws {
        let transport = MockTransport { _ in (200, decisionsBody("0.92")) }
        _ = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128")

        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-6-luna")
        let input = try XCTUnwrap(json["input"] as? String)
        XCTAssertTrue(input.contains("URL: https://www.youtube.com/watch?v=abc"))
        XCTAssertTrue(input.contains("Title: Lo-fi beats"))

        let questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions[0]["type"] as? String, "predicate")
        XCTAssertEqual(questions[0]["name"] as? String, "off_task")
        let instructions = try XCTUnwrap(questions[0]["instructions"] as? String)
        XCTAssertTrue(instructions.contains("CS128"))
        XCTAssertEqual(instructions, DecisionsClient.instructions(subject: "CS128"))
    }

    // MARK: - Response

    func testParsesProbability() async throws {
        let transport = MockTransport { _ in (200, decisionsBody("0.92")) }
        let p = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128")
        XCTAssertEqual(p, 0.92, accuracy: 0.0001)
    }

    func testClampsProbabilityIntoUnitRange() async throws {
        let high = MockTransport { _ in (200, decisionsBody("1.7")) }
        let low = MockTransport { _ in (200, decisionsBody("-0.2")) }
        let pHigh = try await makeClient(high).offTaskProbability(page: page, subject: "CS128")
        let pLow = try await makeClient(low).offTaskProbability(page: page, subject: "CS128")
        XCTAssertEqual(pHigh, 1.0)
        XCTAssertEqual(pLow, 0.0)
    }

    func testFallsBackToFirstPredicateWhenNameDiffers() async throws {
        let transport = MockTransport { _ in
            (200, MockTransport.json(#"{"answers": [{"type": "predicate", "name": "other", "probability": 0.3}]}"#))
        }
        let p = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128")
        XCTAssertEqual(p, 0.3, accuracy: 0.0001)
    }

    func testPrefersTheOffTaskAnswerOverEarlierOnes() async throws {
        let transport = MockTransport { _ in
            (200, MockTransport.json(#"""
            {"answers": [{"type": "predicate", "name": "other", "probability": 0.1},
                         {"type": "predicate", "name": "off_task", "probability": 0.8}]}
            """#))
        }
        let p = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128")
        XCTAssertEqual(p, 0.8, accuracy: 0.0001)
    }

    func testRefusalAnswerThrowsRefusal() async {
        let transport = MockTransport { _ in
            (200, MockTransport.json(#"{"answers": [{"type": "refusal", "name": "off_task"}]}"#))
        }
        await assertThrows(.refusal, transport)
    }

    func testHTTPErrorThrowsStatus() async {
        await assertThrows(.http(401), MockTransport { _ in (401, MockTransport.json(#"{"error": {"message": "bad key"}}"#)) })
        await assertThrows(.http(500), MockTransport { _ in (500, MockTransport.json("")) })
    }

    func testMalformedBodiesThrowDecoding() async {
        await assertThrows(.decoding, MockTransport { _ in (200, MockTransport.json("not json")) })
        await assertThrows(.decoding, MockTransport { _ in (200, MockTransport.json("{}")) })
        await assertThrows(.decoding, MockTransport { _ in (200, MockTransport.json(#"{"answers": []}"#)) })
        await assertThrows(.decoding, MockTransport { _ in
            (200, MockTransport.json(#"{"answers": [{"type": "predicate", "name": "off_task"}]}"#))
        })
    }

    func testTransportErrorIsWrapped() async {
        do {
            _ = try await makeClient(FailingTransport()).offTaskProbability(page: page, subject: "CS128")
            XCTFail("expected a throw")
        } catch let error as DecisionsError {
            guard case .transport = error else { return XCTFail("expected .transport, got \(error)") }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    private func assertThrows(_ expected: DecisionsError, _ transport: MockTransport,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let p = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128")
            XCTFail("expected \(expected), got probability \(p)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? DecisionsError, expected, file: file, line: line)
        }
    }

    // MARK: - Input text

    func testInputTextWithAllFields() {
        let info = PageInfo(url: "https://cs128.org/syllabus", title: "Syllabus", description: "Course policies", siteName: "CS128")
        XCTAssertEqual(DecisionsClient.inputText(info),
                       "URL: https://cs128.org/syllabus\nTitle: Syllabus\nSite: CS128\nDescription: Course policies")
    }

    func testInputTextOmitsMissingSiteAndDescription() {
        let info = PageInfo(url: "https://example.com", title: "Hi", description: nil, siteName: "  ")
        XCTAssertEqual(DecisionsClient.inputText(info), "URL: https://example.com\nTitle: Hi")
    }

    func testInputTextMissingTitleSaysNone() {
        let info = PageInfo(url: "https://example.com", title: "  \n ", description: nil, siteName: nil)
        XCTAssertEqual(DecisionsClient.inputText(info), "URL: https://example.com\nTitle: (none)")
    }

    func testInputTextTrimsAndCollapsesWhitespace() {
        let info = PageInfo(url: " https://example.com ", title: "  Two\n\n lines\t here ",
                            description: "a   b\r\n c", siteName: nil)
        XCTAssertEqual(DecisionsClient.inputText(info),
                       "URL: https://example.com\nTitle: Two lines here\nDescription: a b c")
    }

    func testInputTextCapsTitleAndDescription() {
        let info = PageInfo(url: "https://example.com", title: String(repeating: "t", count: 400),
                            description: String(repeating: "d", count: 600), siteName: nil)
        let lines = DecisionsClient.inputText(info).components(separatedBy: "\n")
        XCTAssertEqual(lines[1], "Title: " + String(repeating: "t", count: 300))
        XCTAssertEqual(lines[2], "Description: " + String(repeating: "d", count: 500))
    }

    func testInstructionsNameTheSubject() {
        let text = DecisionsClient.instructions(subject: "  Organic Chemistry ")
        XCTAssertTrue(text.contains("\"Organic Chemistry\""))
        XCTAssertTrue(text.contains("unrelated"))
    }

    func testInstructionsDoNotTreatAKeywordAsTheWork() {
        let text = DecisionsClient.instructions(subject: "CS128", details: "Intro CS in C++")
        XCTAssertTrue(text.contains("A mention of the subject, a course code, or a word from the description is not enough."))
        XCTAssertTrue(text.contains("even when the title, URL, or description names the work"))
        XCTAssertFalse(text.contains("plausibly"))
    }

    func testInstructionsWithoutDetailsHaveNoDescription() {
        XCTAssertEqual(DecisionsClient.instructions(subject: "CS128", details: "  \n "),
                       DecisionsClient.instructions(subject: "CS128"))
        XCTAssertFalse(DecisionsClient.instructions(subject: "CS128").contains("describes"))
    }

    func testInstructionsCarryTheDescriptionCollapsedAndCapped() {
        let text = DecisionsClient.instructions(subject: "CS128", details: "Intro CS in C++:\n  pointers,   classes")
        XCTAssertTrue(text.contains("\"Intro CS in C++: pointers, classes\""), text)

        let long = DecisionsClient.instructions(subject: "CS128", details: String(repeating: "x", count: DecisionsClient.maxDetailsLength + 300))
        XCTAssertTrue(long.contains(String(repeating: "x", count: DecisionsClient.maxDetailsLength)))
        XCTAssertFalse(long.contains(String(repeating: "x", count: DecisionsClient.maxDetailsLength + 1)))
    }

    func testRequestInstructionsCarryTheDescription() async throws {
        let transport = MockTransport { _ in (200, decisionsBody("0.2")) }
        _ = try await makeClient(transport).offTaskProbability(page: page, subject: "CS128",
                                                               details: "Intro CS in C++")

        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
        let instructions = try XCTUnwrap(questions.first?["instructions"] as? String)
        XCTAssertEqual(instructions, DecisionsClient.instructions(subject: "CS128", details: "Intro CS in C++"))
        XCTAssertFalse(try XCTUnwrap(json["input"] as? String).contains("Intro CS"),
                       "the description is the user's own words, not part of the untrusted page input")
    }
}
