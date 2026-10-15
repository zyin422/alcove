import AppKit
import XCTest
@testable import Tofu

final class CompanionSettingsTests: XCTestCase {
    func testDefaultsAreEnabledEscalation() {
        let settings = AppSettings()
        XCTAssertTrue(settings.companionEnabled)
        XCTAssertEqual(settings.companionPersonality, .escalation)
    }

    /// Settings saved before the companion existed still load, with the new fields at their defaults.
    func testOlderStoreFileFallsBackToCompanionDefaults() throws {
        let json = #"{"displayName":"Alex","discordEnabled":false,"giveUpTemplate":"I give up on {subject}","channelCache":{}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.companionEnabled)
        XCTAssertEqual(settings.companionPersonality, .escalation)
    }

    func testCompanionFieldsRoundTrip() throws {
        var settings = AppSettings()
        settings.companionEnabled = false
        settings.companionPersonality = .yandere
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.companionEnabled)
        XCTAssertEqual(decoded.companionPersonality, .yandere)
    }
    func testBundledPortraitsLoadForEveryExpression() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for expression in [CompanionExpression.neutral, .annoyed, .pleased, .dark] {
            let bundled = try XCTUnwrap(CompanionArt.bundledImage(for: expression))
            XCTAssertGreaterThan(bundled.size.width, 0)
            XCTAssertTrue(CompanionArt.image(for: expression, directory: directory) === bundled)
        }
    }

    func testCustomPortraitOverridesBundleAndInvalidFileFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("neutral.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 7,
            pixelsHigh: 9, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        let custom = try XCTUnwrap(CompanionArt.image(for: .neutral, directory: directory))
        XCTAssertEqual(custom.size.width, 7)
        XCTAssertEqual(custom.size.height, 9)
        try Data("invalid image".utf8).write(to: file)
        XCTAssertTrue(CompanionArt.image(for: .neutral, directory: directory)
            === CompanionArt.bundledImage(for: .neutral))
    }
}
