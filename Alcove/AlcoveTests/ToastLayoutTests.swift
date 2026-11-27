import XCTest
@testable import Alcove

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
}
