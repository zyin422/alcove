import Foundation
import os

/// While locked in, takes a screenshot every `interval` (5 minutes), has it described by the vision model and
/// keeps the description as a `MemoryNote`. Skips quietly when screen memory is off, during a break, without an
/// OpenAI key or without Screen Recording permission. The first shot comes one interval after the lock-in.
@MainActor final class ScreenMemoryRecorder {
    nonisolated static let defaultInterval: TimeInterval = 300

    private let capturer: ScreenCapturing
    private let extractor: ScreenMemoryExtractor
    private let store: MemoryStore
    private let isEnabled: () -> Bool
    private let isPaused: () -> Bool
    private let clock: () -> Date
    private let interval: TimeInterval
    private var loop: Task<Void, Never>?
    private(set) var subject: Subject?

    init(capturer: ScreenCapturing, extractor: ScreenMemoryExtractor, store: MemoryStore,
         isEnabled: @escaping () -> Bool, isPaused: @escaping () -> Bool,
         clock: @escaping () -> Date = { Date() }, interval: TimeInterval = ScreenMemoryRecorder.defaultInterval) {
        self.capturer = capturer
        self.extractor = extractor
        self.store = store
        self.isEnabled = isEnabled
        self.isPaused = isPaused
        self.clock = clock
        self.interval = interval
    }

    func start(subject: Subject) {
        stop()
        self.subject = subject
        let interval = interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.recordNow()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        subject = nil
    }

    /// One capture → describe → remember. Public so tests (and a future "remember now") can drive it.
    @discardableResult
    func recordNow() async -> MemoryNote? {
        guard let subject, isEnabled(), !isPaused() else { return nil }
        guard capturer.hasPermission else {
            Log.session.notice("Screen memory skipped: no Screen Recording permission")
            return nil
        }
        do {
            let jpeg = try await capturer.capture()
            let note = try await extractor.describe(jpeg: jpeg, subject: subject,
                                                    recent: store.notes(for: subject.id), at: clock())
            // The session may have ended while the model was thinking.
            guard self.subject?.id == subject.id else { return nil }
            store.add(note)
            Log.session.info("Remembered a screenshot (\(note.onTask ? "on task" : "off task", privacy: .public))")
            return note
        } catch {
            Log.session.error("Screen memory failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
