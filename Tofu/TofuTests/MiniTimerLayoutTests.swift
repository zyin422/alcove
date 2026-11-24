import XCTest
@testable import Tofu

final class MiniTimerLayoutTests: XCTestCase {
    private let size = CGSize(width: 240, height: 64)

    func testPanelSizeAndMarginMatchTheSpec() {
        XCTAssertEqual(MiniTimerLayout.panelSize, CGSize(width: 240, height: 64))
        XCTAssertEqual(MiniTimerLayout.topMargin, 8)
    }

    func testFrameIsCenteredHorizontallyEightPointsBelowTheTop() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 600, y: 803, width: 240, height: 64))
    }

    func testFrameFollowsTheVisibleFrameOrigin() {
        // Dock on the left and a bottom inset: the panel is centered within the visible frame, not the screen.
        let visible = CGRect(x: 100, y: 50, width: 1200, height: 800)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 580, y: 778, width: 240, height: 64))
    }

    func testCustomTopMargin() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible, topMargin: 20),
                       CGRect(x: 600, y: 791, width: 240, height: 64))
    }

    func testOddWidthRoundsXDownToAWholePoint() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 700)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 380, y: 628, width: 240, height: 64))
    }

    func testPanelWiderThanTheScreenIsPinnedToTheLeftEdge() {
        let visible = CGRect(x: 30, y: 0, width: 200, height: 400)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 30, y: 328, width: 240, height: 64))
    }

    func testSecondaryScreenAboveThePrimary() {
        // A screen stacked above the primary has a positive y origin in Cocoa coordinates.
        let visible = CGRect(x: -200, y: 900, width: 1920, height: 1055)
        XCTAssertEqual(MiniTimerLayout.frame(size: size, visible: visible),
                       CGRect(x: 640, y: 1883, width: 240, height: 64))
    }

    func testSmallMovementIsAClickNotADrag() {
        XCTAssertFalse(MiniTimerLayout.isDrag(from: .zero, to: .zero))
        XCTAssertFalse(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
        XCTAssertFalse(MiniTimerLayout.isDrag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 8, y: 11)))
    }

    func testMovementAtOrBeyondThresholdIsADrag() {
        XCTAssertTrue(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: 3, y: 0)))
        XCTAssertTrue(MiniTimerLayout.isDrag(from: .zero, to: CGPoint(x: -2, y: -3)))
        XCTAssertTrue(MiniTimerLayout.isDrag(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 400, y: 620)))
    }

    func testDraggedOriginMovesByThePointerDelta() {
        let origin = CGPoint(x: 600, y: 803)
        XCTAssertEqual(MiniTimerLayout.draggedOrigin(origin, from: CGPoint(x: 700, y: 830), to: CGPoint(x: 650, y: 800)),
                       CGPoint(x: 550, y: 773))
        XCTAssertEqual(MiniTimerLayout.draggedOrigin(origin, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)),
                       origin)
    }

    // MARK: Tucking

    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testPullDownIsPositiveWhenThePointerMovesDown() {
        XCTAssertEqual(MiniTimerLayout.pullDown(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 10, y: 70)), 30)
        XCTAssertEqual(MiniTimerLayout.pullDown(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 40, y: 100)), 0)
        XCTAssertEqual(MiniTimerLayout.pullDown(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 10, y: 130)), -30)
    }

    func testOnlyTheTopEdgeCountsAsCrossing() {
        let resting = MiniTimerLayout.frame(size: size, visible: visible)
        XCTAssertFalse(MiniTimerLayout.crossedTop(origin: resting.origin, height: size.height, visible: visible))
        let sideways = CGPoint(x: resting.origin.x - 400, y: resting.origin.y)
        XCTAssertFalse(MiniTimerLayout.crossedTop(origin: sideways, height: size.height, visible: visible))
        let past = CGPoint(x: resting.origin.x, y: visible.maxY - size.height + 1)
        XCTAssertTrue(MiniTimerLayout.crossedTop(origin: past, height: size.height, visible: visible))
    }

    func testTuckedTabSitsFlushWithTheTopAndKeepsThePillCenter() {
        let frame = MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible)
        XCTAssertEqual(frame, CGRect(x: 676, y: 853, width: 88, height: 22))
        XCTAssertEqual(frame.midX, 720)
        XCTAssertEqual(frame.maxY, visible.maxY)
    }

    func testRevealedPillSitsJustUnderTheMenuBarAtTheSameCenter() {
        let frame = MiniTimerLayout.revealedFrame(centerX: 200, visible: visible)
        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.midX, 200)
        XCTAssertEqual(frame.maxY, visible.maxY - MiniTimerLayout.topMargin)
    }

    func testPullingTheTabBringsTheFullPillDownWithThePointer() {
        let frame = MiniTimerLayout.pullingFrame(centerX: 720, pullDown: 40, visible: visible)
        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.midX, 720)
        XCTAssertEqual(frame.maxY, visible.maxY - 40)
    }

    func testOpenDragFollowsThePointerEvenAboveTheScreen() {
        let pressOrigin = CGPoint(x: 600, y: 803)
        let frame = MiniTimerLayout.frameDuringDrag(tucked: false, pressOrigin: pressOrigin, pressSize: size,
                                                     pressMouse: CGPoint(x: 700, y: 830),
                                                     mouse: CGPoint(x: 700, y: 900), visible: visible)
        XCTAssertEqual(frame, CGRect(x: 600, y: 873, width: 240, height: 64))
    }

    func testSidewaysDragOfAnOpenPillDoesNotTuck() {
        let origin = CGPoint(x: 200, y: 400)
        let action = MiniTimerLayout.release(tucked: false, dragging: true, origin: origin, size: size,
                                              pullDown: 0, closeHit: false, visible: visible)
        XCTAssertEqual(action, .leave)
    }

    func testReleasingPastTheTopTucksAtThePillCenter() {
        let origin = CGPoint(x: 600, y: 860)
        let action = MiniTimerLayout.release(tucked: false, dragging: true, origin: origin, size: size,
                                              pullDown: -20, closeHit: false, visible: visible)
        XCTAssertEqual(action, .tuck(MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible)))
    }

    func testReleasingNearTopTucksAtThePillCenter() {
        let resting = MiniTimerLayout.frame(size: size, visible: visible)
        let action = MiniTimerLayout.release(tucked: false, dragging: true, origin: resting.origin, size: size,
                                              pullDown: 0, closeHit: false, visible: visible)
        XCTAssertEqual(action, .tuck(MiniTimerLayout.tuckedFrame(centerX: resting.midX, visible: visible)))
    }

    func testReleasingWithinSnapThresholdTucks() {
        // Resting top is 867 (875 - 8). Snap threshold is 50, so origin at 867 - 50 - 64 = 753 is boundary.
        let nearTopOrigin = CGPoint(x: 600, y: 760) // top is 824 >= 817
        let action = MiniTimerLayout.release(tucked: false, dragging: true, origin: nearTopOrigin, size: size,
                                              pullDown: 0, closeHit: false, visible: visible)
        XCTAssertEqual(action, .tuck(MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible)))
    }

    func testReleasingFarBelowTopDoesNotTuck() {
        let farOrigin = CGPoint(x: 600, y: 700) // top is 764 < 817
        let action = MiniTimerLayout.release(tucked: false, dragging: true, origin: farOrigin, size: size,
                                              pullDown: 0, closeHit: false, visible: visible)
        XCTAssertEqual(action, .leave)
    }

    func testAShortPullSnapsTheTabBack() {
        let tab = MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible)
        let action = MiniTimerLayout.release(tucked: true, dragging: true, origin: tab.origin, size: tab.size,
                                              pullDown: 23, closeHit: false, visible: visible)
        XCTAssertEqual(action, .tuck(tab))
    }

    func testALongPullOpensThePill() {
        let tab = MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible)
        let action = MiniTimerLayout.release(tucked: true, dragging: true, origin: tab.origin, size: tab.size,
                                              pullDown: 24, closeHit: false, visible: visible)
        XCTAssertEqual(action, .reveal(MiniTimerLayout.revealedFrame(centerX: 720, visible: visible)))
    }

    func testClickingTheTabLeavesItTuckedAndClickingThePillDoesNot() {
        let tab = MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible)
        let click = MiniTimerLayout.release(tucked: true, dragging: false, origin: tab.origin, size: tab.size,
                                             pullDown: 0, closeHit: false, visible: visible)
        XCTAssertEqual(click, .leave)

        let pill = MiniTimerLayout.frame(size: size, visible: visible)
        XCTAssertEqual(MiniTimerLayout.release(tucked: false, dragging: false, origin: pill.origin, size: pill.size,
                                                pullDown: 0, closeHit: false, visible: visible), .open)
        XCTAssertEqual(MiniTimerLayout.release(tucked: false, dragging: false, origin: pill.origin, size: pill.size,
                                                pullDown: 0, closeHit: true, visible: visible), .end)
    }

    func testAPillDraggedDownFromTheTopStaysAway() {
        let resting = MiniTimerLayout.frame(size: size, visible: visible)
        XCTAssertFalse(MiniTimerLayout.isAwayFromTop(frame: resting, visible: visible))
        let nudged = resting.offsetBy(dx: 0, dy: -(MiniTimerLayout.untuckDistance - 1))
        XCTAssertFalse(MiniTimerLayout.isAwayFromTop(frame: nudged, visible: visible))
        let away = resting.offsetBy(dx: 0, dy: -MiniTimerLayout.untuckDistance)
        XCTAssertTrue(MiniTimerLayout.isAwayFromTop(frame: away, visible: visible))
        XCTAssertFalse(MiniTimerLayout.isAwayFromTop(frame: MiniTimerLayout.tuckedFrame(centerX: 720, visible: visible),
                                                      visible: visible))
        XCTAssertEqual(MiniTimerLayout.visibleBeforeTuck, 3)
    }

    @MainActor func testMiniTimerChromeNotice() {
        let chrome = MiniTimerChrome()
        XCTAssertFalse(chrome.isTucked)
        XCTAssertNil(chrome.noticeText)
        chrome.noticeText = "I set reddit.com aside."
        XCTAssertEqual(chrome.noticeText, "I set reddit.com aside.")
    }

    func testTargetScreenVisible() {
        let screen1 = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible1 = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let screen2 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let visible2 = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let fallback = visible1

        let screens = [screen1, screen2]
        let visFrames = [visible1, visible2]

        // Point inside screen 1
        XCTAssertEqual(MiniTimerLayout.targetScreenVisible(point: CGPoint(x: 500, y: 500), screens: screens, visibleFrames: visFrames, fallback: fallback), visible1)

        // Point inside screen 2
        XCTAssertEqual(MiniTimerLayout.targetScreenVisible(point: CGPoint(x: 1600, y: 500), screens: screens, visibleFrames: visFrames, fallback: fallback), visible2)

        // Point outside all screens
        XCTAssertEqual(MiniTimerLayout.targetScreenVisible(point: CGPoint(x: -500, y: -500), screens: screens, visibleFrames: visFrames, fallback: fallback), fallback)
    }

    func testThoughtAndLockInHitRects() {
        let panelSize = CGSize(width: 240, height: 64)
        // Close hit is near x: 213 (width - 16 - 11)
        XCTAssertTrue(MiniTimerLayout.isCloseHit(CGPoint(x: 213, y: 32), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isThoughtHit(CGPoint(x: 213, y: 32), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isSoundHit(CGPoint(x: 213, y: 32), in: panelSize))

        // Thought button sits immediately to the left of close hit
        let thoughtRect = MiniTimerLayout.thoughtHitRect(in: panelSize)
        let thoughtPoint = CGPoint(x: thoughtRect.midX, y: thoughtRect.midY)
        XCTAssertTrue(MiniTimerLayout.isThoughtHit(thoughtPoint, in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isCloseHit(thoughtPoint, in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isSoundHit(thoughtPoint, in: panelSize))

        // Soundscape button sits immediately to the left of thought button
        let soundRect = MiniTimerLayout.soundHitRect(in: panelSize)
        let soundPoint = CGPoint(x: soundRect.midX, y: soundRect.midY)
        XCTAssertTrue(MiniTimerLayout.isSoundHit(soundPoint, in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isThoughtHit(soundPoint, in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isCloseHit(soundPoint, in: panelSize))

        // Lock in button occupies trailing region
        XCTAssertTrue(MiniTimerLayout.isLockInHit(CGPoint(x: 200, y: 32), in: panelSize))
        XCTAssertTrue(MiniTimerLayout.isLockInHit(CGPoint(x: 160, y: 20), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isLockInHit(CGPoint(x: 100, y: 32), in: panelSize))

        // Resume and Extend break buttons during break
        XCTAssertTrue(MiniTimerLayout.isResumeHit(CGPoint(x: 200, y: 32), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isResumeHit(CGPoint(x: 150, y: 32), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isResumeHit(CGPoint(x: 100, y: 32), in: panelSize))

        XCTAssertTrue(MiniTimerLayout.isExtendBreakHit(CGPoint(x: 150, y: 32), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isExtendBreakHit(CGPoint(x: 200, y: 32), in: panelSize))
        XCTAssertFalse(MiniTimerLayout.isExtendBreakHit(CGPoint(x: 100, y: 32), in: panelSize))
    }

    func testIsNearTopWithGenerousThreshold() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        // At rest: maxY is 875 - 8 = 867
        let resting = MiniTimerLayout.frame(size: size, visible: visible)
        XCTAssertTrue(MiniTimerLayout.isNearTop(origin: resting.origin, height: size.height, visible: visible))

        // Pulled down 60pt: maxY is 807. Within 80pt threshold
        let near = resting.offsetBy(dx: 0, dy: -60)
        XCTAssertTrue(MiniTimerLayout.isNearTop(origin: near.origin, height: size.height, visible: visible))

        // Pulled down 90pt: maxY is 777. Beyond 80pt threshold
        let far = resting.offsetBy(dx: 0, dy: -90)
        XCTAssertFalse(MiniTimerLayout.isNearTop(origin: far.origin, height: size.height, visible: visible))
    }

    func testTargetScreenVisibleResolvesClosestScreenWhenAboveTop() {
        let screen1 = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible1 = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let screen2 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let visible2 = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let fallback = visible1

        let screens = [screen1, screen2]
        let visFrames = [visible1, visible2]

        // Point thrown above menu bar of screen 1 (e.g. y = 920)
        let aboveScreen1 = CGPoint(x: 500, y: 920)
        XCTAssertEqual(MiniTimerLayout.targetScreenVisible(point: aboveScreen1, screens: screens, visibleFrames: visFrames, fallback: fallback), visible1)
    }

    func testIsPositionOnAnyScreenValidatesScreenContainment() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        ]

        // Inside primary display
        XCTAssertTrue(MiniTimerLayout.isPositionOnAnyScreen(CGPoint(x: 100, y: 200), in: screens))
        // Inside secondary display
        XCTAssertTrue(MiniTimerLayout.isPositionOnAnyScreen(CGPoint(x: 1600, y: 500), in: screens))
        // Outside both displays (e.g. disconnected monitor coordinates)
        XCTAssertFalse(MiniTimerLayout.isPositionOnAnyScreen(CGPoint(x: -500, y: 200), in: screens))
        XCTAssertFalse(MiniTimerLayout.isPositionOnAnyScreen(CGPoint(x: 5000, y: 500), in: screens))
    }

    func testCompletedFlowCyclesCalculatesPacedIntervals() {
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 0), 0)
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 14 * 60), 0)
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 24 * 60 + 59), 0)

        // 1 cycle at 25m
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 25 * 60), 1)
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 35 * 60), 1)

        // 2 cycles at 50m
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 50 * 60), 2)

        // 3 cycles at 75m
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 75 * 60), 3)

        // 5 cycles at 125m
        XCTAssertEqual(MiniTimerLayout.completedFlowCycles(elapsed: 125 * 60), 5)
    }
}
