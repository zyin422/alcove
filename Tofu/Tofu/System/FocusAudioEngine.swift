import AVFoundation
import Foundation
import Observation

/// Pure math helpers for audio synthesis (unit-tested).
enum FocusAudioMath {
    /// Brown noise leaky integrator: integrates white noise with decay.
    static func nextBrown(current: Float, white: Float) -> Float {
        (current + (0.02 * white)) / 1.02
    }

    /// Pink noise (Paul Kellet 6-pole filter): shapes white noise into -3 dB/octave spectrum.
    static func nextPink(white: Float, b0: inout Float, b1: inout Float, b2: inout Float,
                         b3: inout Float, b4: inout Float, b5: inout Float, b6: inout Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return pink * 0.11
    }

    /// Single-pole low-pass filter: y[n] = y[n-1] + alpha * (x[n] - y[n-1])
    static func lowPass(current: Float, input: Float, alpha: Float) -> Float {
        current + alpha * (input - current)
    }

    /// Slow sinusoidal wave swell multiplier between (1.0 - depth) and 1.0.
    static func waveSwell(phase: Double, depth: Double = 0.18) -> Float {
        Float((1.0 - depth) + depth * (0.5 + 0.5 * sin(phase * 2.0 * Double.pi)))
    }

    /// Warm polyphonic analog chord pad with subtle detune and soft saturation.
    static func analogChord(time: Double, rootFreq: Double = 130.81) -> Float {
        // C minor 9th harmonics: root (1x), minor third (1.2x), fifth (1.5x), minor seventh (1.8x), ninth (2.25x)
        let r = rootFreq
        let chorus = 0.5 * sin(2.0 * .pi * 0.2 * time)
        let f1 = r + chorus * 0.3
        let f2 = r * 1.2 - chorus * 0.2
        let f3 = r * 1.5 + chorus * 0.4
        let f4 = r * 1.8 - chorus * 0.3
        let f5 = r * 2.25 + chorus * 0.5

        let s1 = sin(2.0 * .pi * f1 * time)
        let s2 = sin(2.0 * .pi * f2 * time)
        let s3 = sin(2.0 * .pi * f3 * time)
        let s4 = sin(2.0 * .pi * f4 * time)
        let s5 = sin(2.0 * .pi * f5 * time)

        let mix = (s1 * 0.35 + s2 * 0.25 + s3 * 0.2 + s4 * 0.15 + s5 * 0.1)
        return Float(tanh(mix * 1.4))
    }

    /// Acoustic raindrop splatter impulse generator with exponential decay.
    static func rainDrop(white: Float, threshold: Float = 0.96, state: inout Float, decay: Float = 0.94) -> Float {
        if white > threshold {
            state = (white - threshold) / (1.0 - threshold)
        } else {
            state *= decay
        }
        return state
    }

    /// Dual-phase non-commensurate stream modulation.
    static func streamModulation(phase1: Double, phase2: Double) -> Float {
        let m1 = 0.5 + 0.5 * sin(phase1 * 2.0 * .pi)
        let m2 = 0.5 + 0.5 * sin(phase2 * 2.0 * .pi)
        return Float(0.4 + 0.6 * (m1 * 0.6 + m2 * 0.4))
    }
}

/// Plays continuous, soothing ambient soundscapes on the Mac's audio hardware
/// using cached audio recordings when available or high-fidelity organic synthesis.
@Observable @MainActor final class FocusAudioEngine: NSObject {
    static let shared = FocusAudioEngine()

    static var audioDirectory: URL {
        Store.defaultURL().deletingLastPathComponent().appendingPathComponent("Audio")
    }

    /// Cycles to the next soundscape in the quick-cycle rotation.
    nonisolated static func nextSound(after current: FocusSound) -> FocusSound {
        let rotation: [FocusSound] = [.off, .rain, .stream, .lofiDrone, .brownNoise]
        guard let idx = rotation.firstIndex(of: current) else { return .rain }
        let nextIdx = (idx + 1) % rotation.count
        return rotation[nextIdx]
    }

    /// Toggles between muted (.off) and a target sound (defaults to .brownNoise or the previous sound).
    nonisolated static func toggleMute(current: FocusSound, fallback: FocusSound = .brownNoise) -> FocusSound {
        current == .off ? (fallback == .off ? .brownNoise : fallback) : .off
    }

    /// System image icon representing the soundscape.
    nonisolated static func iconName(for sound: FocusSound) -> String {
        switch sound {
        case .off: return "speaker.slash"
        case .rain: return "cloud.rain.fill"
        case .stream: return "water.waves"
        case .lofiDrone: return "waveform.badge.magnifyingglass"
        case .brownNoise, .pinkNoise, .whiteNoise: return "waveform"
        case .gammaBinaural, .alphaBinaural, .thetaBinaural: return "brain.head.profile"
        }
    }

    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var activeSound: FocusSound = .off
    var volume: Float = 0.5 {
        didSet {
            if isPlaying && !isPaused {
                engine?.mainMixerNode.outputVolume = volume
                player?.volume = volume
            }
        }
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var preDuckVolume: Float?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?

    /// Smoothly transitions volume to target value over `duration` seconds.
    func fadeVolume(to target: Float, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        fadeTask?.cancel()
        if duration <= 0 {
            engine?.mainMixerNode.outputVolume = target
            player?.volume = target
            completion?()
            return
        }

        player?.setVolume(target, fadeDuration: duration)

        let steps = 12
        let stepDuration = duration / Double(steps)
        let startVol = engine?.mainMixerNode.outputVolume ?? volume
        let delta = (target - startVol) / Float(steps)

        fadeTask = Task { @MainActor [weak self] in
            var currentVol = startVol
            for _ in 0..<steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                if Task.isCancelled { return }
                currentVol += delta
                self?.engine?.mainMixerNode.outputVolume = max(0.0, min(1.0, currentVol))
            }
            self?.engine?.mainMixerNode.outputVolume = target
            completion?()
        }
    }

    /// Starts playing the requested soundscape.
    func play(_ sound: FocusSound, fadeIn: Bool = true) {
        guard sound != .off else {
            stop()
            return
        }
        if isPlaying && activeSound == sound { return }
        stop()

        activeSound = sound

        // First check for a real cached audio file
        if let localURL = findCachedAudio(for: sound) {
            do {
                let audioPlayer = try AVAudioPlayer(contentsOf: localURL)
                audioPlayer.numberOfLoops = -1
                audioPlayer.volume = fadeIn ? 0.0 : volume
                audioPlayer.prepareToPlay()
                audioPlayer.play()
                if fadeIn {
                    audioPlayer.setVolume(volume, fadeDuration: 1.0)
                }
                self.player = audioPlayer
                self.isPlaying = true
                return
            } catch {
                // Fall back to synthesis
            }
        }

        let audioEngine = AVAudioEngine()
        self.engine = audioEngine

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else {
            return
        }
        let sampleRate = Float(format.sampleRate)

        // Filter states (Stereo Decorrelated with Warm Acoustic Shaping)
        var brownLeft: Float = 0.0
        var brownRight: Float = 0.0
        var brownWarmLeft: Float = 0.0
        var brownWarmRight: Float = 0.0

        var b0L: Float = 0.0, b1L: Float = 0.0, b2L: Float = 0.0
        var b3L: Float = 0.0, b4L: Float = 0.0, b5L: Float = 0.0, b6L: Float = 0.0

        var b0R: Float = 0.0, b1R: Float = 0.0, b2R: Float = 0.0
        var b3R: Float = 0.0, b4R: Float = 0.0, b5R: Float = 0.0, b6R: Float = 0.0

        var rainL: Float = 0.0
        var rainR: Float = 0.0
        var dropL: Float = 0.0
        var dropR: Float = 0.0

        var streamL: Float = 0.0
        var streamR: Float = 0.0

        var whiteAirL: Float = 0.0
        var whiteAirR: Float = 0.0

        var brownBedL: Float = 0.0
        var brownBedR: Float = 0.0

        var lfoPhase: Double = 0.0
        var lfoPhase2: Double = 0.0
        var chordTime: Double = 0.0
        var phaseLeft: Double = 0.0
        var phaseRight: Double = 0.0

        let carrierFreq: Double = 136.1 // Grounding, warm OM tone
        let beatDelta: Double
        switch sound {
        case .alphaBinaural: beatDelta = 10.0
        case .thetaBinaural: beatDelta = 6.0
        case .gammaBinaural: beatDelta = 40.0
        default: beatDelta = 0.0
        }

        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2 else { return noErr }

            let leftBuffer = ablPointer[0].mData?.assumingMemoryBound(to: Float.self)
            let rightBuffer = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)

            for frame in 0..<Int(frameCount) {
                switch sound {
                case .off:
                    leftBuffer?[frame] = 0
                    rightBuffer?[frame] = 0

                case .rain:
                    // Multi-layer rain: low-frequency background rumble + random acoustic droplet splatters
                    let whiteL = Float.random(in: -1.0...1.0)
                    let whiteR = Float.random(in: -1.0...1.0)
                    brownLeft = FocusAudioMath.nextBrown(current: brownLeft, white: whiteL)
                    brownRight = FocusAudioMath.nextBrown(current: brownRight, white: whiteR)
                    let bedL = FocusAudioMath.lowPass(current: brownWarmLeft, input: brownLeft, alpha: 0.15) * 0.4
                    let bedR = FocusAudioMath.lowPass(current: brownWarmRight, input: brownRight, alpha: 0.15) * 0.4
                    brownWarmLeft = bedL
                    brownWarmRight = bedR

                    let dropNoiseL = abs(Float.random(in: 0.0...1.0))
                    let dropNoiseR = abs(Float.random(in: 0.0...1.0))
                    let dropImpulseL = FocusAudioMath.rainDrop(white: dropNoiseL, threshold: 0.985, state: &dropL, decay: 0.91)
                    let dropImpulseR = FocusAudioMath.rainDrop(white: dropNoiseR, threshold: 0.985, state: &dropR, decay: 0.91)

                    leftBuffer?[frame] = (bedL * 0.6 + dropImpulseL * 0.35) * 0.5
                    rightBuffer?[frame] = (bedR * 0.6 + dropImpulseR * 0.35) * 0.5

                case .stream:
                    // Babbling forest brook: pink noise shaped by dual non-commensurate sinusoidal currents
                    let whiteL = Float.random(in: -1.0...1.0)
                    let whiteR = Float.random(in: -1.0...1.0)
                    let pinkL = FocusAudioMath.nextPink(white: whiteL, b0: &b0L, b1: &b1L, b2: &b2L,
                                                        b3: &b3L, b4: &b4L, b5: &b5L, b6: &b6L)
                    let pinkR = FocusAudioMath.nextPink(white: whiteR, b0: &b0R, b1: &b1R, b2: &b2R,
                                                        b3: &b3R, b4: &b4R, b5: &b5R, b6: &b6R)
                    streamL = FocusAudioMath.lowPass(current: streamL, input: pinkL, alpha: 0.22)
                    streamR = FocusAudioMath.lowPass(current: streamR, input: pinkR, alpha: 0.22)

                    let modL = FocusAudioMath.streamModulation(phase1: lfoPhase, phase2: lfoPhase2)
                    let modR = FocusAudioMath.streamModulation(phase1: lfoPhase + 0.17, phase2: lfoPhase2 + 0.23)
                    lfoPhase += 0.35 / Double(sampleRate)
                    lfoPhase2 += 0.82 / Double(sampleRate)
                    if lfoPhase > 1.0 { lfoPhase -= 1.0 }
                    if lfoPhase2 > 1.0 { lfoPhase2 -= 1.0 }

                    leftBuffer?[frame] = streamL * modL * 0.4
                    rightBuffer?[frame] = streamR * modR * 0.4

                case .lofiDrone:
                    // Polyphonic analog tape pad
                    let pad = FocusAudioMath.analogChord(time: chordTime, rootFreq: 130.81)
                    chordTime += 1.0 / Double(sampleRate)
                    leftBuffer?[frame] = pad * 0.32
                    rightBuffer?[frame] = pad * 0.32

                case .brownNoise:
                    // Stereo decorrelation + low-frequency rolling ocean swell
                    let whiteL = Float.random(in: -1.0...1.0)
                    let whiteR = Float.random(in: -1.0...1.0)
                    brownLeft = FocusAudioMath.nextBrown(current: brownLeft, white: whiteL)
                    brownRight = FocusAudioMath.nextBrown(current: brownRight, white: whiteR)

                    brownWarmLeft = FocusAudioMath.lowPass(current: brownWarmLeft, input: brownLeft, alpha: 0.28)
                    brownWarmRight = FocusAudioMath.lowPass(current: brownWarmRight, input: brownRight, alpha: 0.28)

                    let swellL = FocusAudioMath.waveSwell(phase: lfoPhase, depth: 0.18)
                    let swellR = FocusAudioMath.waveSwell(phase: lfoPhase + 0.12, depth: 0.18)
                    lfoPhase += 0.07 / Double(sampleRate)
                    if lfoPhase > 1.0 { lfoPhase -= 1.0 }

                    let valL = min(1.0, max(-1.0, brownWarmLeft * 3.6)) * swellL * 0.36
                    let valR = min(1.0, max(-1.0, brownWarmRight * 3.6)) * swellR * 0.36
                    leftBuffer?[frame] = valL
                    rightBuffer?[frame] = valR

                case .pinkNoise:
                    // Stereo decorrelated rainfall with high-cut warmth and subtle rhythmic gusts
                    let whiteL = Float.random(in: -1.0...1.0)
                    let whiteR = Float.random(in: -1.0...1.0)
                    let pinkL = FocusAudioMath.nextPink(white: whiteL, b0: &b0L, b1: &b1L, b2: &b2L,
                                                        b3: &b3L, b4: &b4L, b5: &b5L, b6: &b6L)
                    let pinkR = FocusAudioMath.nextPink(white: whiteR, b0: &b0R, b1: &b1R, b2: &b2R,
                                                        b3: &b3R, b4: &b4R, b5: &b5R, b6: &b6R)

                    rainL = FocusAudioMath.lowPass(current: rainL, input: pinkL, alpha: 0.35)
                    rainR = FocusAudioMath.lowPass(current: rainR, input: pinkR, alpha: 0.35)

                    let swellL = FocusAudioMath.waveSwell(phase: lfoPhase, depth: 0.14)
                    let swellR = FocusAudioMath.waveSwell(phase: lfoPhase + 0.18, depth: 0.14)
                    lfoPhase += 0.11 / Double(sampleRate)
                    if lfoPhase > 1.0 { lfoPhase -= 1.0 }

                    leftBuffer?[frame] = min(1.0, max(-1.0, rainL * 1.8)) * swellL * 0.32
                    rightBuffer?[frame] = min(1.0, max(-1.0, rainR * 1.8)) * swellR * 0.32

                case .whiteNoise:
                    // Diffuse stereo air/breeze without harsh ear-piercing static
                    let whiteL = Float.random(in: -0.22...0.22)
                    let whiteR = Float.random(in: -0.22...0.22)
                    whiteAirL = FocusAudioMath.lowPass(current: whiteAirL, input: whiteL, alpha: 0.40)
                    whiteAirR = FocusAudioMath.lowPass(current: whiteAirR, input: whiteR, alpha: 0.40)

                    let swellL = FocusAudioMath.waveSwell(phase: lfoPhase, depth: 0.12)
                    let swellR = FocusAudioMath.waveSwell(phase: lfoPhase + 0.08, depth: 0.12)
                    lfoPhase += 0.05 / Double(sampleRate)
                    if lfoPhase > 1.0 { lfoPhase -= 1.0 }

                    leftBuffer?[frame] = whiteAirL * swellL * 0.28
                    rightBuffer?[frame] = whiteAirR * swellR * 0.28

                case .alphaBinaural, .thetaBinaural, .gammaBinaural:
                    // Warm harmonic tone + organic ambient bedding
                    let sL = sin(phaseLeft * 2.0 * Double.pi)
                    let hL = sin(phaseLeft * 4.0 * Double.pi)
                    let sR = sin(phaseRight * 2.0 * Double.pi)
                    let hR = sin(phaseRight * 4.0 * Double.pi)

                    phaseLeft += carrierFreq / Double(sampleRate)
                    phaseRight += (carrierFreq + beatDelta) / Double(sampleRate)
                    if phaseLeft > 1.0 { phaseLeft -= 1.0 }
                    if phaseRight > 1.0 { phaseRight -= 1.0 }

                    let wL = Float.random(in: -0.4...0.4)
                    let wR = Float.random(in: -0.4...0.4)
                    brownBedL = FocusAudioMath.nextBrown(current: brownBedL, white: wL)
                    brownBedR = FocusAudioMath.nextBrown(current: brownBedR, white: wR)

                    let toneL = Float(sL) * 0.07 + Float(hL) * 0.015 + brownBedL * 0.12
                    let toneR = Float(sR) * 0.07 + Float(hR) * 0.015 + brownBedR * 0.12

                    leftBuffer?[frame] = toneL
                    rightBuffer?[frame] = toneR
                }
            }
            return noErr
        }

        self.sourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        audioEngine.mainMixerNode.outputVolume = fadeIn ? 0.0 : volume

        do {
            try audioEngine.start()
            isPlaying = true
            if fadeIn {
                fadeVolume(to: volume, duration: 1.0)
            }
        } catch {
            stop()
        }
    }

    private func findCachedAudio(for sound: FocusSound) -> URL? {
        let fm = FileManager.default
        let dir = Self.audioDirectory
        let candidates = [
            sound.rawValue,
            sound.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
            sound.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        ]
        let extensions = ["m4a", "wav", "mp3", "caf", "aif"]
        for name in candidates {
            for ext in extensions {
                let file = dir.appendingPathComponent("\(name).\(ext)")
                if fm.fileExists(atPath: file.path) {
                    return file
                }
            }
        }
        return nil
    }

    /// Stops audio playback and frees audio nodes immediately.
    func stop() {
        performImmediateStop()
    }

    /// Smoothly fades out audio over `duration` seconds before halting.
    func fadeOutAndStop(duration: TimeInterval = 0.6) {
        guard isPlaying else {
            performImmediateStop()
            return
        }
        fadeVolume(to: 0.0, duration: duration) { [weak self] in
            self?.performImmediateStop()
        }
    }

    private func performImmediateStop() {
        fadeTask?.cancel()
        fadeTask = nil
        if let engine, engine.isRunning {
            engine.stop()
        }
        if let sourceNode, let engine {
            engine.detach(sourceNode)
        }
        player?.stop()
        player = nil
        sourceNode = nil
        engine = nil
        isPlaying = false
        isPaused = false
        activeSound = .off
    }

    /// Pauses current playback without deallocating the pipeline, with optional smooth fade-out.
    func pause(fadeOutDuration: TimeInterval = 0) {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        if fadeOutDuration > 0 {
            fadeVolume(to: 0.0, duration: fadeOutDuration) { [weak self] in
                self?.engine?.pause()
                self?.player?.pause()
            }
        } else {
            engine?.pause()
            player?.pause()
        }
    }

    /// Resumes playback if paused, with optional smooth fade-in.
    func resume(fadeInDuration: TimeInterval = 0) {
        guard isPlaying, isPaused else { return }
        isPaused = false
        try? engine?.start()
        player?.play()
        if fadeInDuration > 0 {
            engine?.mainMixerNode.outputVolume = 0.0
            player?.volume = 0.0
            fadeVolume(to: volume, duration: fadeInDuration)
        } else {
            engine?.mainMixerNode.outputVolume = volume
            player?.volume = volume
        }
    }

    /// Ducks audio smoothly while voice assistant is speaking.
    func duck(level: Float = 0.25) {
        guard isPlaying, !isPaused, preDuckVolume == nil else { return }
        preDuckVolume = volume
        let ducked = volume * level
        engine?.mainMixerNode.outputVolume = ducked
        player?.volume = ducked
    }

    /// Restores volume after voice assistant finishes speaking.
    func unduck() {
        guard let original = preDuckVolume else { return }
        preDuckVolume = nil
        engine?.mainMixerNode.outputVolume = original
        player?.volume = original
    }
}
