import XCTest
@testable import Alcove

private func decisionsBody(_ probability: Double) -> Data {
    MockTransport.json(#"{"answers": [{"type": "predicate", "name": "off_task", "probability": \#(probability)}]}"#)
}

private let pageHTML = Data("""
<html><head><title>Fetched Title</title>
<meta name="description" content="Syllabus for CS128">
<meta property="og:site_name" content="Illinois"></head></html>
""".utf8)

/// Mutable key box so tests can change what the judge sees between calls.
private final class KeyBox {
    var key: String?
    init(_ key: String?) { self.key = key }
}

@MainActor
final class RelevanceJudgeTests: XCTestCase {
    private let bare = PageInfo(url: "https://example.edu/syllabus", title: "", description: nil, siteName: nil)

    /// Routes by host: api.openai.com -> decisions JSON with `probability`, anything else -> the page HTML.
    private func routedTransport(probability: Double = 0.1) -> MockTransport {
        MockTransport { request in
            if request.url?.host == "api.openai.com" { return (200, decisionsBody(probability)) }
            return (200, pageHTML)
        }
    }

    private func makeJudge(key: String? = "sk-test", transport: MockTransport) -> RelevanceJudge {
        RelevanceJudge(apiKey: { key }, transport: transport)
    }

    private func decisionsInput(_ transport: MockTransport) throws -> String {
        let request = try XCTUnwrap(transport.requests.first { $0.url?.host == "api.openai.com" })
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(json["input"] as? String)
    }

    // MARK: - Key handling

    func testNoKeyIsUnknownAndMakesNoRequest() async {
        for key in [nil, "", "  \n "] as [String?] {
            let transport = routedTransport()
            let verdict = await makeJudge(key: key, transport: transport).judge(page: bare, subject: "CS128")
            XCTAssertEqual(verdict, .unknown("No OpenAI API key"))
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testKeyIsReadOnEveryJudgeAndTrimmed() async throws {
        let box = KeyBox(nil)
        let transport = routedTransport()
        let judge = RelevanceJudge(apiKey: { box.key }, transport: transport)
        let page = PageInfo(url: "https://example.edu", title: "T", description: "D", siteName: nil)

        let first = await judge.judge(page: page, subject: "CS128")
        XCTAssertEqual(first, .unknown("No OpenAI API key"))

        box.key = "  sk-late \n"
        let second = await judge.judge(page: page, subject: "CS128")
        XCTAssertEqual(second, .relevant)
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-late")
    }

    // MARK: - Threshold

    func testMiddleProbabilityIsUnsure() async {
        let page = PageInfo(url: "https://example.edu", title: "T", description: "D", siteName: nil)
        let verdict = await makeJudge(transport: routedTransport(probability: 0.5)).judge(page: page, subject: "CS128")
        XCTAssertEqual(verdict, .unsure(relevance: 0.5))
    }

    func testLowProbabilityIsRelevant() async {
        let page = PageInfo(url: "https://example.edu", title: "T", description: "D", siteName: nil)
        let verdict = await makeJudge(transport: routedTransport(probability: 0.1)).judge(page: page, subject: "CS128")
        XCTAssertEqual(verdict, .relevant)
    }

    func testVerdictBands() {
        XCTAssertEqual(RelevanceJudge.verdict(offTaskProbability: 0.61), .offTask)        // relevance 0.39
        XCTAssertEqual(RelevanceJudge.verdict(offTaskProbability: 0.6), .unsure(relevance: 1 - 0.6))
        XCTAssertEqual(RelevanceJudge.verdict(offTaskProbability: 0.3), .unsure(relevance: 1 - 0.3))
        XCTAssertEqual(RelevanceJudge.verdict(offTaskProbability: 0.29), .relevant)       // relevance 0.71
        XCTAssertEqual(RelevanceJudge.verdict(offTaskProbability: 1.4), .offTask)
        XCTAssertEqual(RelevanceJudge.verdict(offTaskProbability: -1), .relevant)
    }

    func testHighProbabilityIsOffTask() async {
        let page = PageInfo(url: "https://example.edu", title: "T", description: "D", siteName: nil)
        let verdict = await makeJudge(transport: routedTransport(probability: 0.97)).judge(page: page, subject: "CS128")
        XCTAssertEqual(verdict, .offTask)
    }

    // MARK: - Errors become unknown

    func testRefusalIsUnknown() async {
        let transport = MockTransport { _ in
            (200, MockTransport.json(#"{"answers": [{"type": "refusal", "name": "off_task"}]}"#))
        }
        let page = PageInfo(url: "https://example.edu", title: "T", description: "D", siteName: nil)
        let verdict = await makeJudge(transport: transport).judge(page: page, subject: "CS128")
        guard case .unknown(let reason) = verdict else { return XCTFail("expected unknown, got \(verdict)") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testHTTPErrorIsUnknown() async {
        let transport = MockTransport { _ in (401, MockTransport.json("{}")) }
        let page = PageInfo(url: "https://example.edu", title: "T", description: "D", siteName: nil)
        let verdict = await makeJudge(transport: transport).judge(page: page, subject: "CS128")
        guard case .unknown(let reason) = verdict else { return XCTFail("expected unknown, got \(verdict)") }
        XCTAssertTrue(reason.contains("401"), reason)
    }

    // MARK: - Metadata

    func testMetadataFetchedOnceAndIncludedInDecisionsInput() async throws {
        let transport = routedTransport()
        let verdict = await makeJudge(transport: transport).judge(page: bare, subject: "CS128")

        XCTAssertEqual(verdict, .relevant)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.filter { $0.url?.host == "example.edu" }.count, 1)
        XCTAssertEqual(transport.requests.filter { $0.url?.host == "api.openai.com" }.count, 1)

        let input = try decisionsInput(transport)
        XCTAssertTrue(input.contains("URL: https://example.edu/syllabus"))
        XCTAssertTrue(input.contains("Title: Fetched Title"), input)   // page title was empty, so the fetched one fills in
        XCTAssertTrue(input.contains("Site: Illinois"))
        XCTAssertTrue(input.contains("Description: Syllabus for CS128"))
    }

    func testDescriptionReachesTheDecisionsInstructions() async throws {
        let transport = routedTransport()
        _ = await makeJudge(transport: transport).judge(page: bare, subject: "CS128", details: "Intro CS in C++")

        let request = try XCTUnwrap(transport.requests.first { $0.url?.host == "api.openai.com" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let questions = try XCTUnwrap(json["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.first?["instructions"] as? String,
                       DecisionsClient.instructions(subject: "CS128", details: "Intro CS in C++"))
    }

    func testExistingTitleIsKeptWhenMetadataFetched() async throws {
        let transport = routedTransport()
        let page = PageInfo(url: "https://example.edu/syllabus", title: "Tab Title", description: nil, siteName: nil)
        _ = await makeJudge(transport: transport).judge(page: page, subject: "CS128")

        let input = try decisionsInput(transport)
        XCTAssertTrue(input.contains("Title: Tab Title"))
        XCTAssertFalse(input.contains("Fetched Title"))
        XCTAssertTrue(input.contains("Description: Syllabus for CS128"))
    }

    func testNoPageFetchWhenDescriptionOrSiteNameAlreadyKnown() async {
        let withDescription = routedTransport()
        let page1 = PageInfo(url: "https://example.edu", title: "T", description: "Known", siteName: nil)
        _ = await makeJudge(transport: withDescription).judge(page: page1, subject: "CS128")
        XCTAssertEqual(withDescription.requests.map { $0.url?.host }, ["api.openai.com"])

        let withSite = routedTransport()
        let page2 = PageInfo(url: "https://example.edu", title: "T", description: nil, siteName: "Known")
        _ = await makeJudge(transport: withSite).judge(page: page2, subject: "CS128")
        XCTAssertEqual(withSite.requests.map { $0.url?.host }, ["api.openai.com"])
    }

    func testFailedMetadataFetchStillJudgesFromUrlAndTitle() async throws {
        let transport = MockTransport { request in
            request.url?.host == "api.openai.com" ? (200, decisionsBody(0.9)) : (404, Data())
        }
        let page = PageInfo(url: "https://example.edu/gone", title: "Tab", description: nil, siteName: nil)
        let verdict = await makeJudge(transport: transport).judge(page: page, subject: "CS128")

        XCTAssertEqual(verdict, .offTask)
        let input = try decisionsInput(transport)
        XCTAssertTrue(input.contains("Title: Tab"))
        XCTAssertFalse(input.contains("Description:"))
    }

    func testInjectedMetadataFetcherReplacesNetworkFetch() async throws {
        let transport = routedTransport()
        var fetched: [String] = []
        let judge = RelevanceJudge(apiKey: { "sk-test" }, transport: transport, metadataFetcher: { url in
            fetched.append(url)
            return (title: "Injected", description: "From closure", siteName: nil)
        })
        _ = await judge.judge(page: bare, subject: "CS128")

        XCTAssertEqual(fetched, ["https://example.edu/syllabus"])
        XCTAssertEqual(transport.requests.map { $0.url?.host }, ["api.openai.com"])
        let input = try decisionsInput(transport)
        XCTAssertTrue(input.contains("Title: Injected"))
        XCTAssertTrue(input.contains("Description: From closure"))
    }
}
