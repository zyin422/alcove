import AVFoundation
import Speech
import XCTest
@testable import Accountabilibrosis

/// Pure parts of the voice input and of the chat screen layout; the microphone itself is not exercised.
final class VoiceInputTests: XCTestCase {
    // MARK: Authorization messages

    func testSpeechAuthorizedHasNoMessage() {
        XCTAssertNil(VoiceInput.message(for: SFSpeechRecognizerAuthorizationStatus.authorized))
    }

    func testSpeechDeniedPointsToSystemSettings() {
        let message = VoiceInput.message(for: SFSpeechRecognizerAuthorizationStatus.denied)
        XCTAssertTrue(message?.contains("Speech Recognition") == true)
        XCTAssertTrue(message?.contains("System Settings") == true)
    }

    func testSpeechRestrictedAndNotDeterminedHaveMessages() {
        XCTAssertNotNil(VoiceInput.message(for: SFSpeechRecognizerAuthorizationStatus.restricted))
        XCTAssertNotNil(VoiceInput.message(for: SFSpeechRecognizerAuthorizationStatus.notDetermined))
        XCTAssertNotEqual(VoiceInput.message(for: SFSpeechRecognizerAuthorizationStatus.restricted),
                          VoiceInput.message(for: SFSpeechRecognizerAuthorizationStatus.notDetermined))
    }

    func testMicrophoneAuthorizedHasNoMessage() {
        XCTAssertNil(VoiceInput.message(forMicrophone: AVAuthorizationStatus.authorized))
    }

    func testMicrophoneDeniedPointsToSystemSettings() {
        let message = VoiceInput.message(forMicrophone: AVAuthorizationStatus.denied)
        XCTAssertTrue(message?.contains("Microphone") == true)
        XCTAssertTrue(message?.contains("System Settings") == true)
    }

    func testMicrophoneRestrictedAndNotDeterminedHaveMessages() {
        XCTAssertNotNil(VoiceInput.message(forMicrophone: AVAuthorizationStatus.restricted))
        XCTAssertNotNil(VoiceInput.message(forMicrophone: AVAuthorizationStatus.notDetermined))
    }

    // MARK: Transcript merging

    func testMergedAppendsTranscriptToTypedText() {
        XCTAssertEqual(VoiceInput.merged(base: "can I", transcript: "check piazza"), "can I check piazza")
    }

    func testMergedDoesNotDoubleTheSpaceAfterTypedText() {
        XCTAssertEqual(VoiceInput.merged(base: "can I  ", transcript: "check piazza"), "can I check piazza")
    }

    func testMergedWithEmptyBaseIsJustTheTranscript() {
        XCTAssertEqual(VoiceInput.merged(base: "", transcript: "check piazza"), "check piazza")
        XCTAssertEqual(VoiceInput.merged(base: "   ", transcript: " check piazza "), "check piazza")
    }

    func testMergedWithEmptyTranscriptKeepsTheTypedTextUntouched() {
        XCTAssertEqual(VoiceInput.merged(base: "can I ", transcript: ""), "can I ")
        XCTAssertEqual(VoiceInput.merged(base: "can I ", transcript: "  "), "can I ")
        XCTAssertEqual(VoiceInput.merged(base: "", transcript: ""), "")
    }

    // MARK: Limits and initial state

    func testRecordingStopsAfterSixtySeconds() {
        XCTAssertEqual(VoiceInput.maxDuration, 60)
    }

    @MainActor func testStartsIdleWithoutTouchingTheMicrophone() {
        let voice = VoiceInput()
        XCTAssertFalse(voice.isRecording)
        XCTAssertEqual(voice.transcript, "")
        XCTAssertNil(voice.errorMessage)
        voice.stop()
        XCTAssertFalse(voice.isRecording)
    }
}

/// Pure rules of the chat screen and the locked window's chat layout.
final class ChatLayoutTests: XCTestCase {
    func testCanSendNeedsTextAndAnIdleBot() {
        XCTAssertTrue(ChatInput.canSend("can I check piazza?", isThinking: false))
        XCTAssertFalse(ChatInput.canSend("", isThinking: false))
        XCTAssertFalse(ChatInput.canSend("  \n ", isThinking: false))
        XCTAssertFalse(ChatInput.canSend("hello", isThinking: true))
    }

    func testTrimmedStripsSurroundingWhitespace() {
        XCTAssertEqual(ChatInput.trimmed("  hello \n"), "hello")
    }

    func testWindowStacksBelowSixHundredFortyPoints() {
        XCTAssertTrue(LockedLayout.isStacked(width: 639))
        XCTAssertFalse(LockedLayout.isStacked(width: 640))
        XCTAssertFalse(LockedLayout.isStacked(width: 900))
    }

    func testSidePaneIsFixedAt280() {
        XCTAssertEqual(LockedLayout.sidePaneWidth, 280)
    }

    func testSideTimerIs44PointsWhenThereIsRoomAndShrinksInANarrowPane() {
        XCTAssertEqual(LockedLayout.sideTimerFontSize(paneWidth: 232), 44)
        XCTAssertEqual(LockedLayout.sideTimerFontSize(paneWidth: 150), 30, accuracy: 0.0001)
        XCTAssertEqual(LockedLayout.sideTimerFontSize(paneWidth: 0), 1)
    }
}
