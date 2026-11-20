import AVFoundation
import Darwin
import FluidAudio
import Observation

/// Kokoro voices supported by FluidAudio.
enum KokoroVoice: String, Codable, CaseIterable, Identifiable {
    case heart = "af_heart"
    case bella = "af_bella"
    case adam = "am_adam"
    case michael = "am_michael"
    case emma = "bf_emma"
    case george = "bm_george"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heart: return "Heart (American Warm)"
        case .bella: return "Bella (American Expressive)"
        case .adam: return "Adam (American Calm)"
        case .michael: return "Michael (American Crisp)"
        case .emma: return "Emma (British Gentle)"
        case .george: return "George (British Classical)"
        }
    }
}

/// Reads the study buddy's lines aloud with Kokoro on this Mac.
/// Lazy-loads on first use and automatically unloads after 60 seconds of inactivity to keep memory at ~40 MB.
@Observable @MainActor final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    /// The one speaker. Loading Kokoro twice would keep two copies of the model in memory.
    static let shared = VoiceOutput()

    var voice: KokoroVoice = .heart {
        didSet {
            guard voice != oldValue else { return }
            let wasLoaded = kokoro != nil
            unloadKokoro()
            if wasLoaded {
                warmKokoro()
            }
        }
    }

    /// Master output volume for voice prompts (0.0 to 1.0).
    var volume: Float = 1.0

    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let systemVoice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var kokoro: KokoroAneManager?
    @ObservationIgnored private var load: Task<KokoroAneManager, Error>?
    @ObservationIgnored private var loadFailed = false
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var saying: Task<Void, Never>?
    @ObservationIgnored private var systemBusy = false
    /// Bumped by `stop()`, so a line that finishes loading after the user starts talking is not played.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var unloadTimer: Timer?

    override init() {
        systemVoice = Self.bestVoice()
        super.init()
        synthesizer.delegate = self
        // Lazy load: Kokoro is NOT preloaded at launch, keeping Tofu memory at ~40 MB.
    }

    /// Queues `text` after anything already being said.
    func speak(_ text: String) {
        unloadTimer?.invalidate()
        unloadTimer = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.append(trimmed)
        isSpeaking = true
        drain()
    }

    /// Stops at once (the user started talking).
    func stop() {
        generation += 1
        queue.removeAll()
        saying?.cancel()
        saying = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        systemBusy = false
        isSpeaking = false
        FocusAudioEngine.shared.unduck()
        scheduleAutoUnload()
    }

    /// Unloads the 82M Kokoro model and releases CoreML tensor memory back to macOS.
    func unloadKokoro() {
        unloadTimer?.invalidate()
        unloadTimer = nil
        kokoro = nil
        load = nil
        loadFailed = false
        malloc_zone_pressure_relief(nil, 0)
    }

    private func scheduleAutoUnload(after seconds: TimeInterval = 60) {
        unloadTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.unloadKokoro()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        unloadTimer = timer
    }

    /// Premium beats enhanced beats default; the user's English variant beats other English voices.
    nonisolated static func bestVoice(from voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
                                      preferredLanguage: String = Locale.current.identifier(.bcp47)) -> AVSpeechSynthesisVoice? {
        let english = voices.filter { $0.language.hasPrefix("en") }
        guard !english.isEmpty else { return AVSpeechSynthesisVoice(language: "en-US") }
        return english.max { rank($0, preferredLanguage) < rank($1, preferredLanguage) }
    }

    // MARK: - Kokoro

    /// Starts the download and compile before the first line, so a check-in does not wait on a cold load.
    private func warmKokoro() {
        Task { [weak self] in
            _ = try? await self?.readyKokoro()
        }
    }

    private func readyKokoro() async throws -> KokoroAneManager {
        if let kokoro { return kokoro }
        if loadFailed { throw KokoroUnavailable() }
        if let load { return try await load.value }
        let currentVoice = voice.rawValue
        let task = Task { () -> KokoroAneManager in
            let manager = KokoroAneManager(defaultVoice: currentVoice, version: .v3)
            try await manager.initialize(preloadVoices: [currentVoice])
            return manager
        }
        load = task
        do {
            let manager = try await task.value
            kokoro = manager
            return manager
        } catch {
            load = nil
            loadFailed = true
            throw error
        }
    }

    private func drain() {
        guard saying == nil, player?.isPlaying != true, !systemBusy else { return }
        guard !queue.isEmpty else {
            isSpeaking = false
            FocusAudioEngine.shared.unduck()
            scheduleAutoUnload()
            return
        }
        let text = queue.removeFirst()
        let generation = generation
        let task = Task { await self.say(text, generation: generation) }
        saying = task
        isSpeaking = true
    }

    private func say(_ text: String, generation: Int) async {
        let mine = saying
        defer {
            if saying == mine { saying = nil }
            drain()
        }
        let wav = await kokoroWav(for: text)
        guard generation == self.generation else { return }
        if let wav, startPlayer(wav) { return }
        guard generation == self.generation else { return }
        startSystem(text)
    }

    private func kokoroWav(for text: String) async -> Data? {
        do {
            // Fast fallback: if Kokoro cold-initialization or synthesis takes > 2.0s, return nil to speak immediately via system TTS
            return try await withThrowingTaskGroup(of: Data?.self) { group in
                group.addTask {
                    let manager = try await self.readyKokoro()
                    try Task.checkCancellation()
                    return try await manager.synthesize(text: text, voice: self.voice.rawValue)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    return nil
                }
                let first = try await group.next() ?? nil
                group.cancelAll()
                return first
            }
        } catch {
            return nil
        }
    }

    /// Plays synthesized audio. The finish callback continues the queue.
    private func startPlayer(_ wav: Data) -> Bool {
        guard let player = try? AVAudioPlayer(data: wav) else { return false }
        player.delegate = self
        player.volume = min(1.0, max(0.0, volume))
        self.player = player
        systemBusy = false
        isSpeaking = true
        FocusAudioEngine.shared.duck()
        return player.play()
    }

    private func startSystem(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = systemVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = min(1.0, max(0.0, volume))
        systemBusy = true
        isSpeaking = true
        FocusAudioEngine.shared.duck()
        synthesizer.speak(utterance)
    }

    nonisolated private static func rank(_ voice: AVSpeechSynthesisVoice, _ preferredLanguage: String) -> Int {
        let quality: Int
        switch voice.quality {
        case .premium: quality = 2
        case .enhanced: quality = 1
        default: quality = 0
        }
        let languageMatch = voice.language == preferredLanguage ? 1 : 0
        let novelty = voice.voiceTraits.contains(.isNoveltyVoice) ? -10 : 0
        return quality * 10 + languageMatch * 5 + novelty
    }

    // MARK: Delegates

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.systemFinished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.systemFinished() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playerFinished(player) }
    }

    private func systemFinished() {
        guard !synthesizer.isSpeaking else { return }
        systemBusy = false
        if queue.isEmpty {
            FocusAudioEngine.shared.unduck()
        }
        drain()
    }

    private func playerFinished(_ player: AVAudioPlayer) {
        guard player === self.player else { return }
        self.player = nil
        if queue.isEmpty {
            FocusAudioEngine.shared.unduck()
        }
        drain()
    }
}

private struct KokoroUnavailable: Error {}
