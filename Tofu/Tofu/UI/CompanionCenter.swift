import AppKit
import Foundation

/// Live CompanionReacting: shows Moss, the floating companion, while a session runs and makes it react
/// to what the engine reports. When screen memory has a note from an earlier session on the subject, Moss
/// brings it up a little after the greeting. All timing (bubble, idle chatter, halfway praise) lives here, so the
/// engine stays free of companion state.
@MainActor final class CompanionCenter: CompanionReacting {
    /// How long a line stays in the bubble.
    static let bubbleDuration: TimeInterval = 6
    /// Pause between idle lines while studying.
    static let idleInterval: ClosedRange<TimeInterval> = 300...420

    /// Delay between the greeting and the memory recall.
    static let recallDelay: TimeInterval = 9

    private let settings: () -> AppSettings
    /// The latest memory note for a subject name, if any.
    private let recall: (String) -> String?
    private let state = CompanionState()
    private var panel: CompanionPanel?
    /// Running total of blocked apps + closed tabs this session; drives escalation.
    private var violations = 0
    private var bubbleTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var halfwayTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var recallTask: Task<Void, Never>?

    init(settings: @escaping () -> AppSettings, recall: @escaping (String) -> String? = { _ in nil }) {
        self.settings = settings
        self.recall = recall
    }

    private var personality: CompanionPersonality { settings().companionPersonality }

    func sessionDidStart(subject: String, goalSeconds: TimeInterval?) {
        guard settings().companionEnabled else { return }
        closeTask?.cancel()
        closeTask = nil
        violations = 0
        state.expression = .calm
        state.bubbleText = nil
        if panel == nil { panel = CompanionPanel(state: state) }
        panel?.show()
        say(.sessionStart(subject: subject))
        if let note = recall(subject) {
            recallTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.recallDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.say(.recall(subject: subject, note: note))
            }
        }

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
        recallTask?.cancel()
        recallTask = nil
        guard panel != nil else { return }
        if outcome == .interrupted {
            close()
            return
        }
        // Keep Moss around long enough to deliver the last line.
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
            state.expression = CompanionScript.restingExpression(violations: violations)
        }
    }

    private func close() {
        bubbleTask?.cancel()
        bubbleTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
