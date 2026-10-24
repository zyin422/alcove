import XCTest
@testable import Tofu

final class SidebarPaletteTests: XCTestCase {
    func testRGBConvertsPrimariesAndGrays() {
        let red = SidebarPalette.rgb(.init(h: 0, s: 100, l: 50))
        XCTAssertEqual(red.r, 1, accuracy: 0.001)
        XCTAssertEqual(red.g, 0, accuracy: 0.001)
        XCTAssertEqual(red.b, 0, accuracy: 0.001)
        let blue = SidebarPalette.rgb(.init(h: 240, s: 100, l: 50))
        XCTAssertEqual(blue.b, 1, accuracy: 0.001)
        XCTAssertEqual(blue.r, 0, accuracy: 0.001)
        let gray = SidebarPalette.rgb(.init(h: 123, s: 0, l: 40))
        XCTAssertEqual(gray.r, 0.4, accuracy: 0.001)
        XCTAssertEqual(gray.g, 0.4, accuracy: 0.001)
    }

    func testRGBWrapsHueAndClampsInputs() {
        let wrapped = SidebarPalette.rgb(.init(h: 360 + 120, s: 100, l: 50))
        XCTAssertEqual(wrapped.g, 1, accuracy: 0.001)
        let negative = SidebarPalette.rgb(.init(h: -120, s: 100, l: 50))
        XCTAssertEqual(negative.b, 1, accuracy: 0.001)
        let clamped = SidebarPalette.rgb(.init(h: 0, s: 150, l: 120))
        XCTAssertEqual(clamped.r, 1, accuracy: 0.001)
        XCTAssertEqual(clamped.g, 1, accuracy: 0.001)
    }

    func testSubjectHueIsStableAndFromTheList() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let hue = SidebarPalette.hue(for: id)
        XCTAssertEqual(hue, SidebarPalette.hue(for: id))
        XCTAssertTrue(SidebarPalette.subjectHues.contains(hue))
    }

    func testSubjectsSpreadAcrossHues() {
        let hues = Set((0..<200).map { _ in SidebarPalette.hue(for: UUID()) })
        XCTAssertGreaterThan(hues.count, SidebarPalette.subjectHues.count / 2)
    }

    func testSubjectAccentUsesItsHueAndTheSubjectSaturation() {
        let id = UUID()
        XCTAssertEqual(SidebarPalette.accent(for: id, lightness: 58),
                       SidebarPalette.HSL(h: SidebarPalette.hue(for: id), s: 55, l: 58))
    }

    func testNonSubjectSelectionsUseTheDefaultHue() {
        for item in [SidebarItem.today, .stats, .settings] {
            XCTAssertEqual(SidebarPalette.make(for: item, dark: false).top.h, SidebarPalette.defaultHue)
        }
        XCTAssertEqual(SidebarPalette.make(for: nil, dark: true).top.h, SidebarPalette.defaultHue)
    }

    func testSubjectSelectionUsesItsHue() {
        let id = UUID()
        XCTAssertEqual(SidebarPalette.make(for: .subject(id), dark: false).top.h, SidebarPalette.hue(for: id))
    }

    func testLightChromeIsPaleWithDarkTextAndDarkChromeIsTheReverse() {
        let light = SidebarPalette.make(hue: 250, saturation: 55, dark: false)
        XCTAssertGreaterThan(light.top.l, 70)
        XCTAssertLessThan(light.foreground.l, 30)
        let dark = SidebarPalette.make(hue: 250, saturation: 55, dark: true)
        XCTAssertLessThan(dark.top.l, 30)
        XCTAssertGreaterThan(dark.foreground.l, 90)
        XCTAssertLessThan(dark.bottom.l, dark.top.l)
    }

    func testSaturationIsCapped() {
        XCTAssertEqual(SidebarPalette.make(hue: 0, saturation: 100, dark: false).top.s, 70)
    }
}
