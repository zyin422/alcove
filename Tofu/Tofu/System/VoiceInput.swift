import AVFoundation
import Foundation
import Observation
import Speech

/// Push-to-talk dictation for the chat screen: microphone -> Speech framework -> live `transcript`.
/// Recognition runs on this Mac when the language supports it. A pause finalizes a phrase but the mic
/// stays open until the person taps stop or `maxDuration`. The app is unsandboxed without hardened runtime,
/// so no entitlements are needed;
/// the two usage descriptions in Info.plist are enough for the permission prompts.
@Observable @MainActor final class VoiceInput {
    /// True while the microphone is open.
    private(set) var isRecording = false
    /// Everything recognized so far in the current recording; updates as the person speaks.
    private(set) var transcript = ""
    /// Why dictation could not start or ended badly, in a sentence for the UI. Cleared by the next `start()`.
    private(set) var errorMessage: String?
    /// The last recording failed because Dictation is off in System Settings (the UI offers a button to open it).
    private(set) var needsDictation = false

    /// Longest single recording.
    nonisolated static let maxDuration: TimeInterval = 60
    /// How long the recognizer may keep delivering the last words after the person pressed stop.
    private static let finishGrace: TimeInterval = 2

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sink = BufferSink()
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var graceTask: Task<Void, Never>?
    /// Bumped whenever a recognition ends, so late callbacks of an old recording are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var startCancelled = false
    /// Finalized phrases from earlier utterances in this press-and-talk. The live hypothesis is merged on top.
    @ObservationIgnored private var committed = ""
    /// Latest partial for the current utterance, before it is finalized.
    @ObservationIgnored private var currentPartial = ""

    // MARK: Pure helpers (unit-tested)

    /// Sentence for a speech-recognition permission state, nil when recognition is allowed.
    nonisolated static func message(for status: SFSpeechRecognizerAuthorizationStatus) -> String? {
        switch status {
        case .authorized:
            return nil
        case .denied:
            return "Speech recognition is off for Tofu. Turn it on in System Settings > Privacy & Security > Speech Recognition."
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
            return "Microphone access is off for Tofu. Turn it on in System Settings > Privacy & Security > Microphone."
        case .restricted:
            return "The microphone is restricted on this Mac."
        case .notDetermined:
            return "Microphone access needs your permission before you can talk."
        @unknown default:
            return "The microphone isn't available."
        }
    }

    /// Where Dictation is turned on (macOS 13+). The Speech framework refuses to run while it is off.
    nonisolated static let dictationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    nonisolated static let dictationOffMessage =
        "Voice needs Dictation. Turn it on in System Settings > Keyboard > Dictation, then try again."

    /// True for the errors the Speech framework gives while Siri and Dictation are turned off
    /// (`kLSRErrorDomain` 201 on-device, `kAFAssistantErrorDomain` 1101 / 1700 in the client).
    nonisolated static func isDictationOff(_ error: Error) -> Bool {
        let error = error as NSError
        switch (error.domain, error.code) {
        case ("kLSRErrorDomain", 201), ("kAFAssistantErrorDomain", 1101), ("kAFAssistantErrorDomain", 1700):
            return true
        default:
            return false
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

    /// True when `incoming` is a new utterance, not a longer/shorter revision of `previous`.
    /// The Speech framework often drops the first words and then starts a fresh hypothesis; those
    /// earlier words must be kept, not replaced.
    nonisolated static func utteranceRestarted(previous: String, incoming: String) -> Bool {
        let previous = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty, !incoming.isEmpty else { return false }
        if incoming.hasPrefix(previous) || previous.hasPrefix(incoming) { return false }
        let words: (String) -> [Substring] = { text in
            text.split { $0.isWhitespace || $0.isPunctuation }.filter { !$0.isEmpty }
        }
        guard let firstPrevious = words(previous).first, let firstIncoming = words(incoming).first else {
            return false
        }
        return firstPrevious.caseInsensitiveCompare(firstIncoming) != .orderedSame
    }

    // MARK: Recording

    /// Asks for speech and microphone permission if needed, then opens the microphone and starts transcribing.
    /// Failures end up in `errorMessage`. Already-granted permissions skip the async hop so the first
    /// words after tapping the mic are not eaten while we wait.
    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        startCancelled = false
        defer { isStarting = false }
        errorMessage = nil
        needsDictation = false
        transcript = ""
        committed = ""
        currentPartial = ""

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            speechStatus = .authorized
        } else {
            speechStatus = await Self.requestSpeechAuthorization()
        }
        if let message = Self.message(for: speechStatus) {
            errorMessage = message
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            guard await Self.requestMicrophoneAccess() else {
                errorMessage = Self.message(forMicrophone: AVCaptureDevice.authorizationStatus(for: .audio))
                    ?? "Microphone access wasn't granted."
                return
            }
        }
        guard !startCancelled else { return }

        guard let recognizer = Self.makeRecognizer(), recognizer.isAvailable else {
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
    /// The recognition task is created before the engine so the first buffers are not dropped
    /// while the recognizer warms up.
    private func beginRecognition(with recognizer: SFSpeechRecognizer) {
        graceTask?.cancel()
        releaseRecognition()
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        // No input device gives a 0 Hz format, and installing a tap on it raises an Objective-C exception.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone found."
            return
        }

        let request = Self.makeRequest()
        self.engine = engine
        attach(request, recognizer: recognizer)
        Self.installTap(on: engine.inputNode, format: format, sink: sink)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            errorMessage = "Couldn't open the microphone."
            releaseRecognition()
            return
        }

        isRecording = true
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maxDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func attach(_ request: SFSpeechAudioBufferRecognitionRequest, recognizer: SFSpeechRecognizer) {
        self.request = request
        sink.setRequest(request)
        let current = generation
        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed, dictationOff in
            Task { @MainActor in
                self?.handle(generation: current, text: text, isFinal: isFinal, failed: failed, dictationOff: dictationOff)
            }
        }
    }

    /// Starts a new utterance on the same running engine after Speech finalizes the last phrase.
    private func continueListening() {
        guard isRecording, let engine, engine.isRunning else { return }
        guard let recognizer = Self.makeRecognizer() else { return }
        generation &+= 1
        task?.cancel()
        task = nil
        request = nil
        attach(Self.makeRequest(), recognizer: recognizer)
    }

    /// A partial or final result (or a failure) from the recognizer.
    private func handle(generation current: Int, text: String?, isFinal: Bool, failed: Bool, dictationOff: Bool) {
        guard current == generation else { return }
        if let text {
            if Self.utteranceRestarted(previous: currentPartial, incoming: text) {
                committed = Self.merged(base: committed, transcript: currentPartial)
            }
            currentPartial = text
            transcript = Self.merged(base: committed, transcript: currentPartial)
        }
        guard isFinal || failed else { return }
        if dictationOff {
            errorMessage = Self.dictationOffMessage
            needsDictation = true
            stopCapture()
            releaseRecognition()
            return
        }
        if isFinal {
            if let text {
                committed = Self.merged(base: committed, transcript: text)
                currentPartial = ""
                transcript = committed
            }
            // A pause ends one phrase. Keep listening so the rest of the list is not dropped.
            if isRecording {
                continueListening()
            } else {
                stopCapture()
                releaseRecognition()
            }
            return
        }
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
        sink.setRequest(nil)
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

    /// The recognizer for the user's language, else US English.
    nonisolated private static func makeRecognizer() -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    nonisolated private static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        return request
    }

    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, sink: BufferSink) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            sink.append(buffer)
        }
    }

    nonisolated private static func startTask(recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              onUpdate: @escaping @Sendable (_ text: String?, _ isFinal: Bool, _ failed: Bool,
                                                                             _ dictationOff: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil,
                     error.map(isDictationOff) ?? false)
        }
    }
}

/// Lets the audio tap keep appending after Speech finalizes an utterance and we swap in a new request.
private final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }
}
