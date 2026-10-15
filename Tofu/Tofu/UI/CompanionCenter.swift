import AppKit
import Foundation

/// Live CompanionReacting: shows the floating companion while a session runs and makes her react
/// to what the engine reports. All timing (bubble, idle chatter, halfway praise) lives here, so the
/// engine stays free of companion state.
@MainActor final class CompanionCenter: CompanionReacting {
    /// How long a line stays in the bubble.
    static let bubbleDuration: TimeInterval = 6
    /// Pause between idle lines while studying.
    static let idleInterval: ClosedRange<TimeInterval> = 300...420

    private let settings: () -> AppSettings
    private let state = CompanionState()
    private var panel: CompanionPanel?
    /// Running total of blocked apps + closed tabs this session; drives escalation.
    private var violations = 0
    private var bubbleTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var halfwayTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    init(settings: @escaping () -> AppSettings) {
        self.settings = settings
    }

    private var personality: CompanionPersonality { settings().companionPersonality }

    func sessionDidStart(subject: String, goalSeconds: TimeInterval?) {
        guard settings().companionEnabled else { return }
        closeTask?.cancel()
        closeTask = nil
        violations = 0
        state.expression = .neutral
        state.bubbleText = nil
        if panel == nil { panel = CompanionPanel(state: state) }
        panel?.show()
        say(.sessionStart(subject: subject))

        if let goalSeconds, goalSeconds > 0 {
            halfwayTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(goalSeconds / 2 * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.say(.halfway)
            }
        }
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = TimeInterval.random(in: Self.idleInterval)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.say(.idle)
            }
        }
    }

    func violationOccurred(_ kind: CompanionViolation, subject: String, violations: Int) {
        guard panel != nil else { return }
        self.violations = violations
        switch kind {
        case .app(let name): say(.blockedApp(name: name))
        case .tab(let host): say(.closedTab(host: host))
        }
    }

    func sessionDidEnd(outcome: SessionOutcome, subject: String) {
        idleTask?.cancel()
        idleTask = nil
        halfwayTask?.cancel()
        halfwayTask = nil
        guard panel != nil else { return }
        if outcome == .interrupted {
            close()
            return
        }
        // Keep her around long enough to deliver the last line.
        say(outcome == .bailed ? .forfeit : .completed)
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.bubbleDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func say(_ event: CompanionEvent) {
        let line = CompanionScript.line(for: event, personality: personality, violations: violations)
        state.expression = line.expression
        state.bubbleText = line.text
        bubbleTask?.cancel()
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.bubbleDuration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            state.bubbleText = nil
            // Resting face: dark once escalated into yandere, neutral otherwise.
            state.expression = CompanionScript.mood(for: personality, violations: violations) == .yandere
                ? .dark : .neutral
        }
    }

    private func close() {
        bubbleTask?.cancel()
        bubbleTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
