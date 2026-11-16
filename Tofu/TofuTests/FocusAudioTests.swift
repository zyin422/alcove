import XCTest
@testable import Tofu

final class FocusAudioTests: XCTestCase {
    func testBrownNoiseLeakyIntegrator() {
        var current: Float = 0.0
        for _ in 0..<100 {
            current = FocusAudioMath.nextBrown(current: current, white: 0.5)
        }
        // Leaky integration should stabilize around white / 0.02 * 0.02 = white
        XCTAssertGreaterThan(current, 0.4)
        XCTAssertLessThan(current, 0.6)

        // Negative white noise pushes it down
        for _ in 0..<200 {
            current = FocusAudioMath.nextBrown(current: current, white: -0.5)
        }
        XCTAssertLessThan(current, 0.0)
    }

    func testPinkNoiseFilterStabilization() {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

        var sum: Float = 0.0
        for _ in 0..<1000 {
            let pink = FocusAudioMath.nextPink(white: 0.2, b0: &b0, b1: &b1, b2: &b2,
                                               b3: &b3, b4: &b4, b5: &b5, b6: &b6)
            sum += pink
        }
        XCTAssertFalse(sum.isNaN)
        XCTAssertFalse(sum.isInfinite)
    }

    func testFocusSoundCodableRoundtrip() throws {
        for sound in FocusSound.allCases {
            let encoded = try JSONEncoder().encode(sound)
            let decoded = try JSONDecoder().decode(FocusSound.self, from: encoded)
            XCTAssertEqual(decoded, sound)
        }
    }

    func testAppSettingsFocusSoundBackwardsCompatibility() throws {
        let legacyJSON = "{}".data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(settings.focusSound, .off)
        XCTAssertEqual(settings.focusSoundVolume, 0.5)
    }

    @MainActor
    func testFocusAudioEngineStateTransitions() {
        let engine = FocusAudioEngine.shared
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.activeSound, .off)

        engine.play(.off)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.activeSound, .off)

        engine.volume = 0.8
        XCTAssertEqual(engine.volume, 0.8)
    }

    @MainActor
    func testFocusAudioPauseAndResume() {
        let engine = FocusAudioEngine.shared
        engine.play(.alphaBinaural)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertFalse(engine.isPaused)

        engine.pause()
        XCTAssertTrue(engine.isPaused)

        engine.resume()
        XCTAssertFalse(engine.isPaused)

        engine.stop()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isPaused)
    }
}
