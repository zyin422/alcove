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
}

/// Synthesizes continuous, soothing ambient soundscapes on the Mac's audio hardware
/// without audio file assets or network latency.
@Observable @MainActor final class FocusAudioEngine: NSObject {
    static let shared = FocusAudioEngine()

    private(set) var isPlaying = false
    private(set) var activeSound: FocusSound = .off
    var volume: Float = 0.5 {
        didSet {
            engine?.mainMixerNode.outputVolume = isPlaying ? volume : 0
        }
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?

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

        // Filter states
        var brownState: Float = 0.0
        var b0: Float = 0.0, b1: Float = 0.0, b2: Float = 0.0
        var b3: Float = 0.0, b4: Float = 0.0, b5: Float = 0.0, b6: Float = 0.0
        var phaseLeft: Double = 0.0
        var phaseRight: Double = 0.0

        let carrierFreq: Double = 180.0
        let beatDelta: Double
        switch sound {
        case .alphaBinaural: beatDelta = 10.0
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
                    let white = Float.random(in: -1.0...1.0)
                    brownState = FocusAudioMath.nextBrown(current: brownState, white: white)
                    let val = min(1.0, max(-1.0, brownState * 3.5)) * 0.35
                    leftBuffer?[frame] = val
                    rightBuffer?[frame] = val

                case .pinkNoise:
                    let white = Float.random(in: -1.0...1.0)
                    let pink = FocusAudioMath.nextPink(white: white, b0: &b0, b1: &b1, b2: &b2,
                                                       b3: &b3, b4: &b4, b5: &b5, b6: &b6)
                    let val = min(1.0, max(-1.0, pink)) * 0.35
                    leftBuffer?[frame] = val
                    rightBuffer?[frame] = val

                case .alphaBinaural, .gammaBinaural:
                    let sL = sin(phaseLeft * 2.0 * Double.pi)
                    let sR = sin(phaseRight * 2.0 * Double.pi)

                    phaseLeft += carrierFreq / Double(sampleRate)
                    phaseRight += (carrierFreq + beatDelta) / Double(sampleRate)
                    if phaseLeft > 1.0 { phaseLeft -= 1.0 }
                    if phaseRight > 1.0 { phaseRight -= 1.0 }

                    leftBuffer?[frame] = Float(sL) * 0.12
                    rightBuffer?[frame] = Float(sR) * 0.12
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
        activeSound = .off
    }
}
