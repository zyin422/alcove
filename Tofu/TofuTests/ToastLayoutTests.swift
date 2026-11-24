import XCTest
@testable import Tofu

final class ToastLayoutTests: XCTestCase {
    private let size = CGSize(width: 320, height: 56)
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testToastSizeIs320Wide() {
        XCTAssertEqual(ToastLayout.toastSize, CGSize(width: 320, height: 56))
        XCTAssertEqual(ToastLayout.margin, 16)
        XCTAssertEqual(ToastLayout.gap, 8)
    }

    func testFirstToastSitsInTopRightCornerInsideMargin() {
        XCTAssertEqual(ToastLayout.frame(index: 0, size: size, visible: visible, margin: 16),
                       CGRect(x: 1104, y: 803, width: 320, height: 56))
    }

    func testEachNextToastStacksBelowWithEightPointGap() {
        XCTAssertEqual(ToastLayout.frame(index: 1, size: size, visible: visible, margin: 16),
                       CGRect(x: 1104, y: 739, width: 320, height: 56))
        XCTAssertEqual(ToastLayout.frame(index: 2, size: size, visible: visible, margin: 16),
                       CGRect(x: 1104, y: 675, width: 320, height: 56))
    }

    func testStackedToastsNeverOverlap() {
        for index in 0..<3 {
            let upper = ToastLayout.frame(index: index, size: size, visible: visible, margin: 16)
            let lower = ToastLayout.frame(index: index + 1, size: size, visible: visible, margin: 16)
            XCTAssertEqual(upper.minY - lower.maxY, 8)
        }
    }

    func testUsesVisibleFrameOriginForOffsetScreens() {
        let offset = CGRect(x: 100, y: 50, width: 800, height: 600)
        XCTAssertEqual(ToastLayout.frame(index: 0, size: size, visible: offset, margin: 16),
                       CGRect(x: 564, y: 578, width: 320, height: 56))
    }

    func testNegativeIndexIsTreatedAsTop() {
        XCTAssertEqual(ToastLayout.frame(index: -1, size: size, visible: visible, margin: 16),
                       ToastLayout.frame(index: 0, size: size, visible: visible, margin: 16))
    }

    func testToastClassificationShield() {
        let (cat1, msg1) = ToastContentParser.classify("🔒 Discord is blocked during CS128")
        XCTAssertEqual(cat1, .shield)
        XCTAssertEqual(msg1, "Discord is blocked during CS128")

        let (cat2, msg2) = ToastContentParser.classify("Closed reddit.com — not relevant to MATH241")
        XCTAssertEqual(cat2, .shield)
        XCTAssertEqual(msg2, "Closed reddit.com — not relevant to MATH241")
    }

    func testToastClassificationGrace() {
        let (cat, msg) = ToastContentParser.classify("🛡️ Grace pass active: 2 minutes to complete your task.")
        XCTAssertEqual(cat, .grace)
        XCTAssertEqual(msg, "Grace pass active: 2 minutes to complete your task.")
    }

    func testToastClassificationRest() {
        let (cat, msg) = ToastContentParser.classify("Break extended +2m ☕️")
        XCTAssertEqual(cat, .rest)
        XCTAssertEqual(msg, "Break extended +2m")
    }

    func testToastClassificationCompleted() {
        let (cat, msg) = ToastContentParser.classify("Saved: 45m on CS128")
        XCTAssertEqual(cat, .completed)
        XCTAssertEqual(msg, "Saved: 45m on CS128")
    }

    func testToastClassificationTelemetryFallback() {
        let (cat, msg) = ToastContentParser.classify("Microphone permission granted.")
        XCTAssertEqual(cat, .telemetry)
        XCTAssertEqual(msg, "Microphone permission granted.")
    }
}
