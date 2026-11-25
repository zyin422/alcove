import XCTest
@testable import Alcove

final class VoiceCoachingTests: XCTestCase {
    func testKokoroVoiceCasesAndDisplayNames() {
        XCTAssertEqual(KokoroVoice.allCases.count, 6)
        XCTAssertEqual(KokoroVoice.heart.rawValue, "af_heart")
        XCTAssertEqual(KokoroVoice.adam.rawValue, "am_adam")
        XCTAssertEqual(KokoroVoice.emma.rawValue, "bf_emma")

        for voice in KokoroVoice.allCases {
            XCTAssertFalse(voice.displayName.isEmpty)
            XCTAssertFalse(voice.id.isEmpty)
        }
    }

    func testAppSettingsVoiceCoachingDefaultsAndDecoding() throws {
        let defaults = AppSettings()
        XCTAssertEqual(defaults.kokoroVoice, .heart)
        XCTAssertEqual(defaults.voiceVolume, 1.0)

        // Backward compatibility
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(decoded.kokoroVoice, .heart)
        XCTAssertEqual(decoded.voiceVolume, 1.0)

        // Custom values roundtrip
        var modified = defaults
        modified.kokoroVoice = .adam
        modified.voiceVolume = 0.75
        let encoded = try JSONEncoder().encode(modified)
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(roundTripped.kokoroVoice, .adam)
        XCTAssertEqual(roundTripped.voiceVolume, 0.75)
    }

    @MainActor
    func testFocusAudioDuckingAndUnducking() {
        let audio = FocusAudioEngine.shared
        audio.play(.brownNoise)
        audio.volume = 0.8
        XCTAssertTrue(audio.isPlaying)

        // Duck
        audio.duck(level: 0.25)
        // Unduck restores original volume
        audio.unduck()
        XCTAssertEqual(audio.volume, 0.8)

        audio.stop()
        XCTAssertFalse(audio.isPlaying)
    }

    @MainActor
    func testVoiceOutputVolumeAndVoiceAssignment() {
        let voiceOut = VoiceOutput.shared
        voiceOut.volume = 0.65
        XCTAssertEqual(voiceOut.volume, 0.65)

        voiceOut.voice = .bella
        XCTAssertEqual(voiceOut.voice, .bella)

        // Reset to default
        voiceOut.voice = .heart
        voiceOut.volume = 1.0
    }
}
