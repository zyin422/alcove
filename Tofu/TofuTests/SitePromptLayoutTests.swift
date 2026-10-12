import AVFoundation
import XCTest
@testable import Tofu

final class SitePromptLayoutTests: XCTestCase {
    func testPanelSitsInTheBottomRightCorner() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = SitePromptLayout.frame(visible: visible)
        XCTAssertEqual(frame.maxX, visible.maxX - SitePromptLayout.margin)
        XCTAssertEqual(frame.minY, visible.minY + SitePromptLayout.margin)
        XCTAssertEqual(frame.size, SitePromptLayout.panelSize)
    }

    func testCountdownRoundsUpAndStopsAtZero() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(SitePromptLayout.countdown(until: now.addingTimeInterval(60), now: now), "Closes in 1:00")
        XCTAssertEqual(SitePromptLayout.countdown(until: now.addingTimeInterval(41.2), now: now), "Closes in 0:42")
        XCTAssertEqual(SitePromptLayout.countdown(until: now.addingTimeInterval(-5), now: now), "Closes in 0:00")
    }

    @MainActor func testBestVoiceIsEnglishWhenAnyEnglishVoiceExists() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard voices.contains(where: { $0.language.hasPrefix("en") }) else { return }
        XCTAssertTrue(VoiceOutput.bestVoice(from: voices, preferredLanguage: "en-US")?.language.hasPrefix("en") == true)
    }
}
