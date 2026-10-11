import AVFoundation
import Observation

/// Reads the study buddy's lines aloud with a built-in macOS voice (on this Mac, no network, no key).
/// The best installed English voice is used: premium, then enhanced, then the default.
@Observable @MainActor final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let voice: AVSpeechSynthesisVoice?

    override init() {
        voice = Self.bestVoice()
        super.init()
        synthesizer.delegate = self
    }

    /// Queues `text` after anything already being said.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stops at once (the user started talking).
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Premium beats enhanced beats default; the user's English variant beats other English voices.
    nonisolated static func bestVoice(from voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
                                      preferredLanguage: String = Locale.current.identifier(.bcp47)) -> AVSpeechSynthesisVoice? {
        let english = voices.filter { $0.language.hasPrefix("en") }
        guard !english.isEmpty else { return AVSpeechSynthesisVoice(language: "en-US") }
        return english.max { rank($0, preferredLanguage) < rank($1, preferredLanguage) }
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

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = self.synthesizer.isSpeaking }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = self.synthesizer.isSpeaking }
    }
}
