import AVFoundation
import Foundation
import Observation
import Speech

/// Push-to-talk dictation for the chat screen: microphone -> Speech framework -> live `transcript`.
/// Recognition runs on this Mac when the language supports it. Capture stops by itself after the final
/// result or `maxDuration`. The app is unsandboxed without hardened runtime, so no entitlements are needed;
/// the two usage descriptions in Info.plist are enough for the permission prompts.
@Observable @MainActor final class VoiceInput {
    /// True while the microphone is open.
    private(set) var isRecording = false
    /// Everything recognized so far in the current recording; updates as the person speaks.
    private(set) var transcript = ""
    /// Why dictation could not start or ended badly, in a sentence for the UI. Cleared by the next `start()`.
    private(set) var errorMessage: String?

    /// Longest single recording.
    nonisolated static let maxDuration: TimeInterval = 60
    /// How long the recognizer may keep delivering the last words after the person pressed stop.
    private static let finishGrace: TimeInterval = 2

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var graceTask: Task<Void, Never>?
    /// Bumped whenever a recognition ends, so late callbacks of an old recording are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var startCancelled = false

    // MARK: Pure helpers (unit-tested)

    /// Sentence for a speech-recognition permission state, nil when recognition is allowed.
    nonisolated static func message(for status: SFSpeechRecognizerAuthorizationStatus) -> String? {
        switch status {
        case .authorized:
            return nil
        case .denied:
            return "Speech recognition is off for Accountabilibrosis. Turn it on in System Settings > Privacy & Security > Speech Recognition."
        case .restricted:
            return "Speech recognition is restricted on this Mac."
        case .notDetermined:
            return "Speech recognition needs your permission before you can talk."
        @unknown default:
            return "Speech recognition isn't available."
        }
    }

    /// Sentence for a microphone permission state, nil when the microphone is allowed.
    nonisolated static func message(forMicrophone status: AVAuthorizationStatus) -> String? {
        switch status {
        case .authorized:
            return nil
        case .denied:
            return "Microphone access is off for Accountabilibrosis. Turn it on in System Settings > Privacy & Security > Microphone."
        case .restricted:
            return "The microphone is restricted on this Mac."
        case .notDetermined:
            return "Microphone access needs your permission before you can talk."
        @unknown default:
            return "The microphone isn't available."
        }
    }

    /// `base` (what was typed before dictating) followed by the live `transcript`, one space apart.
    /// An empty transcript leaves `base` exactly as typed.
    nonisolated static func merged(base: String, transcript: String) -> String {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return base }
        let typed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? spoken : typed + " " + spoken
    }

    // MARK: Recording

    /// Asks for speech and microphone permission if needed, then opens the microphone and starts transcribing.
    /// Failures end up in `errorMessage`.
    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        startCancelled = false
        defer { isStarting = false }
        errorMessage = nil
        transcript = ""

        let speechStatus = await Self.requestSpeechAuthorization()
        if let message = Self.message(for: speechStatus) {
            errorMessage = message
            return
        }
        guard await Self.requestMicrophoneAccess() else {
            errorMessage = Self.message(forMicrophone: AVCaptureDevice.authorizationStatus(for: .audio))
                ?? "Microphone access wasn't granted."
            return
        }
        guard !startCancelled else { return }

        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        beginRecognition(with: recognizer)
    }

    /// Closes the microphone. The last words may still arrive in `transcript` for a moment.
    func stop() {
        if isStarting { startCancelled = true }
        guard isRecording else { return }
        stopCapture()
        graceTask?.cancel()
        let current = generation
        graceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.finishGrace * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.releaseRecognition()
        }
    }

    // MARK: Internals

    /// Opens the microphone and starts a live recognition task on `recognizer`.
    private func beginRecognition(with recognizer: SFSpeechRecognizer) {
        graceTask?.cancel()
        releaseRecognition()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        // No input device gives a 0 Hz format, and installing a tap on it raises an Objective-C exception.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone found."
            return
        }
        Self.installTap(on: engine.inputNode, format: format, request: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            errorMessage = "Couldn't open the microphone."
            return
        }

        self.engine = engine
        self.request = request
        let current = generation
        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in
                self?.handle(generation: current, text: text, isFinal: isFinal, failed: failed)
            }
        }
        isRecording = true
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maxDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// A partial or final result (or a failure) from the recognizer.
    private func handle(generation current: Int, text: String?, isFinal: Bool, failed: Bool) {
        guard current == generation else { return }
        if let text {
            transcript = text
        }
        guard isFinal || failed else { return }
        if failed, isRecording, transcript.isEmpty {
            errorMessage = "I didn't catch that. Try again."
        }
        stopCapture()
        releaseRecognition()
    }

    /// Closes the microphone and tells the recognizer no more audio is coming.
    private func stopCapture() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        request?.endAudio()
        isRecording = false
    }

    /// Drops the recognition task; callbacks of the old recording are ignored from here on.
    private func releaseRecognition() {
        generation &+= 1
        graceTask?.cancel()
        graceTask = nil
        task?.cancel()
        task = nil
        request = nil
    }

    // MARK: Framework callbacks
    // Kept nonisolated: these closures run on audio and Speech queues, never on the main actor.

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startTask(recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              onUpdate: @escaping @Sendable (_ text: String?, _ isFinal: Bool, _ failed: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}
