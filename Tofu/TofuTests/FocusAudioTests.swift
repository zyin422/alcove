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

    func testLowPassFilterStability() {
        var current: Float = 0.0
        for _ in 0..<100 {
            current = FocusAudioMath.lowPass(current: current, input: 1.0, alpha: 0.2)
        }
        XCTAssertGreaterThan(current, 0.99)
        XCTAssertLessThanOrEqual(current, 1.0)
    }

    func testWaveSwellBounds() {
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let swell = FocusAudioMath.waveSwell(phase: p, depth: 0.18)
            XCTAssertGreaterThanOrEqual(swell, 0.81)
            XCTAssertLessThanOrEqual(swell, 1.01)
        }
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

    func testAnalogChordGeneratesBoundedHarmonicWave() {
        for t in stride(from: 0.0, through: 1.0, by: 0.01) {
            let sample = FocusAudioMath.analogChord(time: t, rootFreq: 130.81) // C3
            XCTAssertFalse(sample.isNaN)
            XCTAssertGreaterThanOrEqual(sample, -1.0)
            XCTAssertLessThanOrEqual(sample, 1.0)
        }
    }

    func testRainSplatterGeneratesTransientImpulse() {
        var state: Float = 0.0
        // High white noise trigger above threshold generates acoustic drop
        let drop = FocusAudioMath.rainDrop(white: 0.98, threshold: 0.95, state: &state, decay: 0.92)
        XCTAssertGreaterThan(drop, 0.0)
        // Subsequent zero noise decays the droplet smoothly
        let decayed = FocusAudioMath.rainDrop(white: 0.0, threshold: 0.95, state: &state, decay: 0.92)
        XCTAssertLessThan(decayed, drop)
    }

    @MainActor
    func testAudioCacheDirectoryConfiguration() {
        let dir = FocusAudioEngine.audioDirectory
        XCTAssertTrue(dir.path.contains("Tofu/Audio"))
    }

    func testNextSoundRotation() {
        XCTAssertEqual(FocusAudioEngine.nextSound(after: .off), .rain)
        XCTAssertEqual(FocusAudioEngine.nextSound(after: .rain), .stream)
        XCTAssertEqual(FocusAudioEngine.nextSound(after: .stream), .lofiDrone)
        XCTAssertEqual(FocusAudioEngine.nextSound(after: .lofiDrone), .brownNoise)
        XCTAssertEqual(FocusAudioEngine.nextSound(after: .brownNoise), .off)
    }

    func testToggleMute() {
        // When active, muting sets to .off
        XCTAssertEqual(FocusAudioEngine.toggleMute(current: .rain), .off)
        XCTAssertEqual(FocusAudioEngine.toggleMute(current: .brownNoise), .off)

        // When off, unmuting restores fallback
        XCTAssertEqual(FocusAudioEngine.toggleMute(current: .off, fallback: .stream), .stream)
        XCTAssertEqual(FocusAudioEngine.toggleMute(current: .off, fallback: .off), .brownNoise)
    }

    @MainActor
    func testFocusAudioFadeTransitions() async {
        let engine = FocusAudioEngine.shared
        engine.volume = 0.8
        engine.play(.brownNoise, fadeIn: false)
        XCTAssertTrue(engine.isPlaying)

        var completed = false
        engine.fadeVolume(to: 0.2, duration: 0.05) {
            completed = true
        }
        try? await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertTrue(completed)

        engine.stop()
        XCTAssertFalse(engine.isPlaying)
    }

    @MainActor
    func testFocusAudioFadeOutAndStop() async {
        let engine = FocusAudioEngine.shared
        engine.play(.brownNoise, fadeIn: false)
        XCTAssertTrue(engine.isPlaying)

        engine.fadeOutAndStop(duration: 0.05)
        try? await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.activeSound, .off)
    }

    func testFocusMusicModePlaylistRoutingAndLegacyMigration() throws {
        XCTAssertEqual(FocusAudioEngine.targetPlaylist(for: .off, isLocked: true, isOnBreak: false), nil)
        XCTAssertEqual(FocusAudioEngine.targetPlaylist(for: .adaptive, isLocked: true, isOnBreak: false), .focus)
        XCTAssertEqual(FocusAudioEngine.targetPlaylist(for: .adaptive, isLocked: true, isOnBreak: true), .relaxed)
        XCTAssertEqual(FocusAudioEngine.targetPlaylist(for: .adaptive, isLocked: false, isOnBreak: false), .relaxed)
        XCTAssertEqual(FocusAudioEngine.targetPlaylist(for: .focus, isLocked: false, isOnBreak: false), .focus)
        XCTAssertEqual(FocusAudioEngine.targetPlaylist(for: .relaxed, isLocked: true, isOnBreak: false), .relaxed)

        let legacySoundJSON = #"{"displayName":"Z","focusSound":"Gentle Rain"}"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(AppSettings.self, from: legacySoundJSON)
        XCTAssertEqual(migrated.focusMusicMode, .adaptive)
        XCTAssertEqual(migrated.quickThoughtShortcut, .controlSpace)

        XCTAssertEqual(
            FocusAudioEngine.formattedTrackTitle(for: URL(fileURLWithPath: "/tmp/town_theme.mp3")),
            "Town Theme"
        )
    }

    @MainActor
    func testBundledCC0PlaylistsContainTracks() {
        let focus = FocusAudioEngine.tracks(for: .focus, bundle: Bundle.main)
        let relaxed = FocusAudioEngine.tracks(for: .relaxed, bundle: Bundle.main)
        XCTAssertGreaterThanOrEqual(focus.count, 3)
        XCTAssertGreaterThanOrEqual(relaxed.count, 3)
    }
}
