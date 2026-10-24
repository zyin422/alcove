import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Takes one screenshot of the main display as a downscaled JPEG (for the vision model, never saved to disk).
@MainActor protocol ScreenCapturing: AnyObject {
    /// True when macOS allows screen recording for Tofu.
    var hasPermission: Bool { get }
    func capture() async throws -> Data
}

enum ScreenCaptureError: Error, Equatable {
    case noPermission
    case noDisplay
    case encoding
}

/// Live capturer: ScreenCaptureKit's one-shot screenshot of the display under the menu bar, Tofu's own windows
/// left out, scaled so the long side is at most `maxPixels`.
@MainActor final class ScreenCapturer: ScreenCapturing {
    static let maxPixels = 1600
    static let jpegQuality = 0.6

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the macOS prompt once; afterwards the user has to allow Tofu in System Settings.
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    func capture() async throws -> Data {
        guard hasPermission else { throw ScreenCaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        let size = Self.scaledSize(width: display.width, height: display.height, maxPixels: Self.maxPixels)
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: Self.jpegQuality]) else {
            throw ScreenCaptureError.encoding
        }
        return data
    }

    /// Fits `width`x`height` inside `maxPixels` on its long side, keeping the aspect ratio. Pure.
    nonisolated static func scaledSize(width: Int, height: Int, maxPixels: Int) -> (width: Int, height: Int) {
        let longSide = max(width, height)
        guard longSide > maxPixels, longSide > 0 else { return (width, height) }
        let factor = Double(maxPixels) / Double(longSide)
        return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
    }
}
