import XCTest
@testable import Alcove

final class LayoutEngineTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testEveryPresetHasOneChromeFramePerSiteAndAnAppFrameOnlyWhenItHasAZone() {
        for preset in LayoutPreset.allCases {
            let result = LayoutEngine.layout(preset, in: screen)
            XCTAssertEqual(result.chromeFrames.count, preset.siteCount, "\(preset)")
            XCTAssertEqual(result.appFrame != nil, preset.appHasZone, "\(preset)")
        }
    }

    func testPresetCountsAndAppFrameNilness() {
        let split = LayoutEngine.layout(.split, in: screen)
        XCTAssertEqual(split.chromeFrames.count, 2)
        XCTAssertNil(split.appFrame)

        let full = LayoutEngine.layout(.full, in: screen)
        XCTAssertEqual(full.chromeFrames.count, 1)
        XCTAssertNil(full.appFrame)

        let thirds = LayoutEngine.layout(.thirds, in: screen)
        XCTAssertEqual(thirds.chromeFrames.count, 2)
        XCTAssertNotNil(thirds.appFrame)

        let mainSide = LayoutEngine.layout(.mainSide, in: screen)
        XCTAssertEqual(mainSide.chromeFrames.count, 1)
        XCTAssertNotNil(mainSide.appFrame)
    }

    func testSplitMakesTwoEqualHalves() {
        XCTAssertEqual(LayoutEngine.layout(.split, in: screen), LayoutResult(chromeFrames: [
            CGRect(x: 0, y: 0, width: 500, height: 800),
            CGRect(x: 500, y: 0, width: 500, height: 800),
        ], appFrame: nil))
    }

    func testFullUsesTheWholeVisibleArea() {
        XCTAssertEqual(LayoutEngine.layout(.full, in: screen),
                       LayoutResult(chromeFrames: [screen], appFrame: nil))
    }

    func testThirdsPutsAppFirstAndLastZoneAbsorbsRemainder() {
        let result = LayoutEngine.layout(.thirds, in: screen)
        XCTAssertEqual(result.appFrame, CGRect(x: 0, y: 0, width: 333, height: 800))
        XCTAssertEqual(result.chromeFrames, [
            CGRect(x: 333, y: 0, width: 333, height: 800),
            CGRect(x: 666, y: 0, width: 334, height: 800),
        ])
    }

    func testMainSideIsSeventyThirtyWithChromeOnTheLeft() {
        let result = LayoutEngine.layout(.mainSide, in: screen)
        XCTAssertEqual(result.chromeFrames, [CGRect(x: 0, y: 0, width: 700, height: 800)])
        XCTAssertEqual(result.appFrame, CGRect(x: 700, y: 0, width: 300, height: 800))
    }

    func testOddWidthRemainderGoesToTheLastZone() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 800)
        XCTAssertEqual(LayoutEngine.layout(.split, in: visible).chromeFrames.map(\.width), [500, 501])
        let thirds = LayoutEngine.layout(.thirds, in: visible)
        XCTAssertEqual(thirds.appFrame?.width, 333)
        XCTAssertEqual(thirds.chromeFrames.map(\.width), [333, 335])
        let mainSide = LayoutEngine.layout(.mainSide, in: visible)
        XCTAssertEqual(mainSide.chromeFrames.map(\.width), [700])
        XCTAssertEqual(mainSide.appFrame?.width, 301)
    }

    func testNonZeroOriginAndFullHeightArePreserved() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)

        XCTAssertEqual(LayoutEngine.layout(.split, in: visible).chromeFrames, [
            CGRect(x: 100, y: 50, width: 500, height: 700),
            CGRect(x: 600, y: 50, width: 500, height: 700),
        ])

        let thirds = LayoutEngine.layout(.thirds, in: visible)
        XCTAssertEqual(thirds.appFrame, CGRect(x: 100, y: 50, width: 333, height: 700))
        XCTAssertEqual(thirds.chromeFrames, [
            CGRect(x: 433, y: 50, width: 333, height: 700),
            CGRect(x: 766, y: 50, width: 334, height: 700),
        ])

        let mainSide = LayoutEngine.layout(.mainSide, in: visible)
        XCTAssertEqual(mainSide.chromeFrames, [CGRect(x: 100, y: 50, width: 700, height: 700)])
        XCTAssertEqual(mainSide.appFrame, CGRect(x: 800, y: 50, width: 300, height: 700))

        for preset in LayoutPreset.allCases {
            let result = LayoutEngine.layout(preset, in: visible)
            for zone in result.chromeFrames + [result.appFrame].compactMap({ $0 }) {
                XCTAssertEqual(zone.minY, 50, "\(preset)")
                XCTAssertEqual(zone.height, 700, "\(preset)")
            }
        }
    }

    func testZonesCoverTheWidthExactlyWithNoGapsOrOverlap() {
        for width in [CGFloat(1000), 1001, 1512, 1728] {
            let visible = CGRect(x: 0, y: 25, width: width, height: 900)
            for preset in LayoutPreset.allCases {
                let label = "\(preset) @ \(width)"
                let result = LayoutEngine.layout(preset, in: visible)
                let zones = (result.chromeFrames + [result.appFrame].compactMap({ $0 }))
                    .sorted { $0.minX < $1.minX }
                XCTAssertEqual(zones.first?.minX, visible.minX, label)
                XCTAssertEqual(zones.last?.maxX, visible.maxX, label)
                for (left, right) in zip(zones, zones.dropFirst()) {
                    XCTAssertEqual(left.maxX, right.minX, label)
                }
                XCTAssertEqual(zones.reduce(CGFloat(0)) { $0 + $1.width }, width, label)
                for zone in zones {
                    XCTAssertEqual(zone.width, zone.width.rounded(.down), "whole points: \(label)")
                    XCTAssertEqual(zone.minY, visible.minY, label)
                    XCTAssertEqual(zone.height, visible.height, label)
                }
            }
        }
    }
}
