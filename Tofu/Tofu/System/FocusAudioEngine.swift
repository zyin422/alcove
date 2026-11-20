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
}

/// Synthesizes continuous, soothing ambient soundscapes on the Mac's audio hardware
/// without audio file assets or network latency.
@Observable @MainActor final class FocusAudioEngine: NSObject {
    static let shared = FocusAudioEngine()

    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var activeSound: FocusSound = .off
    var volume: Float = 0.5 {
        didSet {
            if isPlaying && !isPaused {
                engine?.mainMixerNode.outputVolume = volume
            }
        }
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var preDuckVolume: Float?

    /// Starts playing the requested soundscape.
    func play(_ sound: FocusSound) {
        guard sound != .off else {
            stop()
            return
        }
        if isPlaying && activeSound == sound { return }
        stop()

        activeSound = sound
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

        var whiteAirL: Float = 0.0
        var whiteAirR: Float = 0.0

        var brownBedL: Float = 0.0
        var brownBedR: Float = 0.0

        var lfoPhase: Double = 0.0
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
        audioEngine.mainMixerNode.outputVolume = volume

        do {
            try audioEngine.start()
            isPlaying = true
        } catch {
            stop()
        }
    }

    /// Stops audio playback and frees audio nodes.
    func stop() {
        if let engine, engine.isRunning {
            engine.stop()
        }
        if let sourceNode, let engine {
            engine.detach(sourceNode)
        }
        engine = nil
        sourceNode = nil
        isPlaying = false
        isPaused = false
        activeSound = .off
        preDuckVolume = nil
    }

    /// Pauses focus sound during break intervals.
    func pause() {
        guard isPlaying, !isPaused else { return }
        isPaused = true
        engine?.mainMixerNode.outputVolume = 0
    }

    /// Resumes focus sound after break intervals finish.
    func resume() {
        guard isPlaying, isPaused else { return }
        isPaused = false
        engine?.mainMixerNode.outputVolume = volume
    }

    /// Temporarily ducks the background audio volume during voice output.
    func duck(level: Float = 0.25) {
        guard isPlaying else { return }
        if preDuckVolume == nil { preDuckVolume = volume }
        let clamped = max(0.0, min(1.0, level))
        engine?.mainMixerNode.outputVolume = volume * clamped
    }

    /// Restores background audio volume after voice output completes.
    func unduck() {
        guard isPlaying, let original = preDuckVolume else { return }
        engine?.mainMixerNode.outputVolume = original
        preDuckVolume = nil
    }
}
