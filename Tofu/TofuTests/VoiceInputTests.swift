import AVFoundation
import Speech
import XCTest
@testable import Tofu

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

    // MARK: Dictation off

    func testSiriAndDictationDisabledErrorsAreRecognized() {
        XCTAssertTrue(VoiceInput.isDictationOff(NSError(domain: "kLSRErrorDomain", code: 201)))
        XCTAssertTrue(VoiceInput.isDictationOff(NSError(domain: "kAFAssistantErrorDomain", code: 1101)))
        XCTAssertTrue(VoiceInput.isDictationOff(NSError(domain: "kAFAssistantErrorDomain", code: 1700)))
        XCTAssertFalse(VoiceInput.isDictationOff(NSError(domain: "kAFAssistantErrorDomain", code: 1110)))
        XCTAssertFalse(VoiceInput.isDictationOff(URLError(.notConnectedToInternet)))
    }

    func testDictationOffMessagePointsToKeyboardSettings() {
        XCTAssertTrue(VoiceInput.dictationOffMessage.contains("Keyboard > Dictation"))
        XCTAssertEqual(VoiceInput.dictationSettingsURL.scheme, "x-apple.systempreferences")
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

    func testUtteranceRevisionIsNotARestart() {
        XCTAssertFalse(VoiceInput.utteranceRestarted(previous: "I need to finish", incoming: "I need to finish the lab"))
        XCTAssertFalse(VoiceInput.utteranceRestarted(previous: "I need to finish the lab", incoming: "I need to finish"))
        XCTAssertFalse(VoiceInput.utteranceRestarted(previous: "", incoming: "read some books"))
        XCTAssertFalse(VoiceInput.utteranceRestarted(previous: "read some books", incoming: ""))
    }

    func testUtteranceRestartKeepsTheFirstWords() {
        XCTAssertTrue(VoiceInput.utteranceRestarted(previous: "I need to finish the lab", incoming: "then review chapter 4"))
        XCTAssertEqual(
            VoiceInput.merged(base: "I need to finish the lab", transcript: "then review chapter 4"),
            "I need to finish the lab then review chapter 4"
        )
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

    // MARK: Hands-Free Silence Detection (VAD)

    @MainActor func testSilenceDetectionFiresOnSpeechEnded() {
        let voice = VoiceInput()
        var silenceHandler: (@MainActor () -> Void)?
        voice.scheduleSilence = { timeout, action in
            XCTAssertEqual(timeout, 1.8)
            silenceHandler = action
        }
        voice.autoStopSilenceTimeout = 1.8
        var endedTranscript: String?
        voice.onSpeechEnded = { endedTranscript = $0 }

        voice.handleResult(text: "what should I focus on next")
        XCTAssertEqual(voice.transcript, "what should I focus on next")
        XCTAssertNil(endedTranscript)

        silenceHandler?()
        XCTAssertEqual(endedTranscript, "what should I focus on next")
    }

    @MainActor func testSilenceDetectionNotTriggeredWhenTranscriptIsEmpty() {
        let voice = VoiceInput()
        var scheduled = false
        voice.scheduleSilence = { _, _ in scheduled = true }
        voice.autoStopSilenceTimeout = 1.8

        voice.handleResult(text: "")
        XCTAssertFalse(scheduled)
    }

    @MainActor func testManualStopCancelsSilenceDetection() {
        let voice = VoiceInput()
        var silenceHandler: (@MainActor () -> Void)?
        voice.scheduleSilence = { _, action in silenceHandler = action }
        voice.autoStopSilenceTimeout = 1.8
        var endedTranscript: String?
        voice.onSpeechEnded = { endedTranscript = $0 }

        voice.handleResult(text: "testing cancel")
        voice.stop()
        silenceHandler?()
        // Should not fire because stop bumped generation
        XCTAssertNil(endedTranscript)
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
