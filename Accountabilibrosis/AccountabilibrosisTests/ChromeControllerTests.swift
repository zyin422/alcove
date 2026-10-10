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
}
