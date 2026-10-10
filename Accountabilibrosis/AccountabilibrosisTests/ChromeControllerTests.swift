import XCTest
@testable import Accountabilibrosis

/// Exercises ChromeController.run with plain AppleScript that never talks to Chrome (or any other app).
@MainActor final class ChromeControllerTests: XCTestCase {
    func testRunReturnsTextResult() {
        XCTAssertEqual(ChromeController.run(#"return "hello""#), .success("hello"))
    }

    func testRunCoercesIntegerResultToText() {
        XCTAssertEqual(ChromeController.run("return 7"), .success("7"))
    }

    func testRunMapsErrorMinus1743ToAutomationDenied() {
        XCTAssertEqual(ChromeController.run(#"error "Not authorized" number -1743"#), .failure(.automationDenied))
    }

    func testRunMapsOtherErrorsToScriptFailedWithMessage() {
        XCTAssertEqual(ChromeController.run(#"error "boom" number 42"#), .failure(.scriptFailed("boom")))
    }

    func testRunReportsCompileErrorsAsScriptFailed() {
        guard case .failure(.scriptFailed(let message)) = ChromeController.run("set x to (") else {
            return XCTFail("expected .scriptFailed for a syntax error")
        }
        XCTAssertFalse(message.isEmpty)
    }

    // MARK: openAll (prepare's per-site loop)

    /// Records every script handed to `openAll` and answers from `results` (missing key = success).
    private func runOpenAll(_ scripts: [String], results: [String: ChromeError]) async -> (ChromeError?, [String]) {
        var attempted: [String] = []
        let error = await ChromeController.openAll(scripts) { script in
            attempted.append(script)
            return results[script]
        }
        return (error, attempted)
    }

    func testOpenAllReturnsNilWhenEverySiteOpens() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"], results: [:])
        XCTAssertNil(error)
        XCTAssertEqual(attempted, ["a", "b", "c"])
    }

    func testOpenAllKeepsOpeningRemainingSitesAfterProfileNotReady() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"], results: ["a": .profileNotReady])
        XCTAssertEqual(error, .profileNotReady)
        XCTAssertEqual(attempted, ["a", "b", "c"])
    }

    func testOpenAllReturnsTheFirstErrorWhenSeveralSitesFail() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"],
                                                  results: ["b": .scriptFailed("first"), "c": .profileNotReady])
        XCTAssertEqual(error, .scriptFailed("first"))
        XCTAssertEqual(attempted, ["a", "b", "c"])
    }

    func testOpenAllStopsImmediatelyOnAutomationDenied() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"], results: ["b": .automationDenied])
        XCTAssertEqual(error, .automationDenied)
        XCTAssertEqual(attempted, ["a", "b"])
    }

    func testOpenAllAutomationDeniedWinsOverEarlierSoftFailure() async {
        let (error, attempted) = await runOpenAll(["a", "b", "c"],
                                                  results: ["a": .profileNotReady, "b": .automationDenied])
        XCTAssertEqual(error, .automationDenied)
        XCTAssertEqual(attempted, ["a", "b"])
    }

    func testOpenAllStopsImmediatelyOnNotInstalled() async {
        let (error, attempted) = await runOpenAll(["a", "b"], results: ["a": .notInstalled])
        XCTAssertEqual(error, .notInstalled)
        XCTAssertEqual(attempted, ["a"])
    }

    func testOpenAllWithNoScriptsSucceeds() async {
        let (error, attempted) = await runOpenAll([], results: [:])
        XCTAssertNil(error)
        XCTAssertEqual(attempted, [])
    }
}
