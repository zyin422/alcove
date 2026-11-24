import Foundation

/// Breathing pacing techniques for cognitive reset and physiological down-regulation.
enum BreathingTechnique: String, CaseIterable, Identifiable, Sendable {
    case box = "Box Breathing (4-4-4-4)"
    case relax = "4-7-8 Relaxing"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .box: return "Box (4-4-4-4)"
        case .relax: return "Relaxing (4-7-8)"
        }
    }
}

/// The current phase within a single breath cycle.
enum BreathingPhase: String, Equatable, Sendable {
    case inhale = "Inhale"
    case holdIn = "Hold"
    case exhale = "Exhale"
    case holdOut = "Rest"
}

/// Instantaneous state of the breath pacer.
struct BreathingState: Equatable, Sendable {
    let phase: BreathingPhase
    let phaseElapsed: TimeInterval
    let phaseDuration: TimeInterval
    let progress: Double
    let instruction: String
}

/// An ergonomic physical desk stretch for screen workers.
struct BreakStretch: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let instructions: String
    let iconName: String
    let durationSeconds: Int
}

/// Pure engine for calculating guided break breath pacing, eye recovery intervals, and stretches.
enum BreakGuide {
    /// Total duration of one complete breathing cycle in seconds.
    static func cycleDuration(for technique: BreathingTechnique) -> TimeInterval {
        switch technique {
        case .box:
            return 16.0 // 4s inhale + 4s hold + 4s exhale + 4s hold
        case .relax:
            return 19.0 // 4s inhale + 7s hold + 8s exhale
        }
    }

    /// Evaluates current breath pacer phase and progress given elapsed seconds into the cycle.
    static func breathingState(technique: BreathingTechnique, cycleElapsed: TimeInterval) -> BreathingState {
        let totalCycle = cycleDuration(for: technique)
        let normalized = max(0, cycleElapsed).truncatingRemainder(dividingBy: totalCycle)

        switch technique {
        case .box:
            if normalized < 4.0 {
                let dur: TimeInterval = 4.0
                return BreathingState(phase: .inhale, phaseElapsed: normalized, phaseDuration: dur, progress: normalized / dur, instruction: "Breathe in deeply through your nose")
            } else if normalized < 8.0 {
                let dur: TimeInterval = 4.0
                let el = normalized - 4.0
                return BreathingState(phase: .holdIn, phaseElapsed: el, phaseDuration: dur, progress: el / dur, instruction: "Hold your breath gently")
            } else if normalized < 12.0 {
                let dur: TimeInterval = 4.0
                let el = normalized - 8.0
                return BreathingState(phase: .exhale, phaseElapsed: el, phaseDuration: dur, progress: el / dur, instruction: "Exhale slowly through your mouth")
            } else {
                let dur: TimeInterval = 4.0
                let el = normalized - 12.0
                return BreathingState(phase: .holdOut, phaseElapsed: el, phaseDuration: dur, progress: el / dur, instruction: "Rest and remain calm")
            }

        case .relax:
            if normalized < 4.0 {
                let dur: TimeInterval = 4.0
                return BreathingState(phase: .inhale, phaseElapsed: normalized, phaseDuration: dur, progress: normalized / dur, instruction: "Inhale quietly through your nose")
            } else if normalized < 11.0 {
                let dur: TimeInterval = 7.0
                let el = normalized - 4.0
                return BreathingState(phase: .holdIn, phaseElapsed: el, phaseDuration: dur, progress: el / dur, instruction: "Hold your breath")
            } else {
                let dur: TimeInterval = 8.0
                let el = normalized - 11.0
                return BreathingState(phase: .exhale, phaseElapsed: el, phaseDuration: dur, progress: el / dur, instruction: "Exhale completely making a whoosh sound")
            }
        }
    }

    /// Default ergonomic micro-stretches for screen fatigue.
    static let stretches: [BreakStretch] = [
        BreakStretch(
            id: "neck",
            title: "Neck Rolls & Release",
            instructions: "Drop your chin to your chest, roll smoothly to the left shoulder, hold 5 seconds, then slowly to the right.",
            iconName: "figure.walk",
            durationSeconds: 30
        ),
        BreakStretch(
            id: "chest",
            title: "Chest & Shoulder Opener",
            instructions: "Interlace fingers behind your back, gently lift your chest, and draw shoulder blades together. Release thoracic hunch.",
            iconName: "figure.arms.open",
            durationSeconds: 30
        ),
        BreakStretch(
            id: "wrist",
            title: "Wrist & Forearm Flex",
            instructions: "Extend one arm with palm facing forward. Gently pull fingers back with other hand, then invert downward.",
            iconName: "hand.raised",
            durationSeconds: 30
        )
    ]
}
