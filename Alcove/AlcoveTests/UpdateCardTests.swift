import SwiftUI
import XCTest
@testable import Alcove

/// The sidebar update card renders at sidebar width as a compact pop-up.
@MainActor final class UpdateCardTests: XCTestCase {
    func testCardRendersCompactlyAtSidebarWidth() throws {
        let card = UpdateCard(version: "1.2", onUpdate: {}, onDismiss: {})
            .frame(width: 208)
            .padding(12)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 232, accuracy: 1)
        XCTAssertGreaterThan(image.size.height, 90)
        XCTAssertLessThan(image.size.height, 150)

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("UpdateCard.png"))
    }
}
