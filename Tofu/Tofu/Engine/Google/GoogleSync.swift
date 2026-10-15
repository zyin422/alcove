import AppKit
import Foundation
import Observation

/// Polls Google and routes local mutations (spec §3–§4). Owned by AppModel; all closures read it.
@Observable @MainActor final class GoogleSync {
    private let api: GoogleAPI
    private let settings: () -> AppSettings
    private let isConnected: () -> Bool
    private let plan: () -> DayPlan
    private let applyPlan: (DayPlan) -> Void
    private let saveCalendarID: (String?) -> Void
    private let onError: (String) -> Void
    private let now: () -> Date

    private(set) var todayEvents: [GoogleEvent] = []
    @ObservationIgnored private var pendingSessions: [Session] = []
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var isApplyingRemote = false
    @ObservationIgnored private var lastCycleFailed = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    init(api: GoogleAPI,
         settings: @escaping () -> AppSettings,
         isConnected: @escaping () -> Bool,
         plan: @escaping () -> DayPlan,
         applyPlan: @escaping (DayPlan) -> Void,
         saveCalendarID: @escaping (String?) -> Void,
         onError: @escaping (String) -> Void = { _ in },
         now: @escaping () -> Date = Date.init) {
        self.api = api
        self.settings = settings
        self.isConnected = isConnected
        self.plan = plan
        self.applyPlan = applyPlan
        self.saveCalendarID = saveCalendarID
        self.onError = onError
        self.now = now
    }

    /// Starts the 60 s poll and a sync on every app activation.
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        Task { await syncNow() }
    }

    /// Tears down the timer and the activation observer.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
    }

    /// Runs one sync cycle; no-op when disconnected, all toggles are off, or a cycle is in flight.
    func syncNow() async {
        let current = settings()
        guard isConnected(), !isSyncing,
              current.googleTasksSyncEnabled || current.googleSessionLogEnabled || current.googleShowEventsEnabled
        else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            if current.googleTasksSyncEnabled { try await syncTasks() }
            if current.googleSessionLogEnabled { try await pushPendingSessions() }
            if current.googleShowEventsEnabled { try await pullEvents() }
            lastCycleFailed = false
        } catch GoogleAuthError.revoked {
            // The auth already dropped the token; the UI shows Connect again. Stay quiet.
        } catch {
            report(error)
        }
    }

    /// Reports only the transition into failure, so a persistent outage does not spam.
    private func report(_ error: Error) {
        if !lastCycleFailed { onError("Google sync failed: \(error)") }
        lastCycleFailed = true
    }

    private func dueStamp() -> String {
        GoogleEventTime.rfc3339.string(from: Calendar.current.startOfDay(for: now()))
    }

    /// Writes a plan through `applyPlan` without letting it echo back into `planChanged`.
    private func applyRemote(_ updated: DayPlan) {
        isApplyingRemote = true
        applyPlan(updated)
        isApplyingRemote = false
    }

    private func syncTasks() async throws {
        let remote = try await api.listTasks()
        var (priorities, toInsert) = GoogleTaskMerge.apply(remote: remote, to: plan().priorities, now: now())
        for pending in toInsert {
            let inserted = try await api.insertTask(title: pending.title, due: dueStamp())
            if let index = priorities.firstIndex(where: { $0.id == pending.id }) {
                priorities[index].googleTaskID = inserted.id
            }
        }
        var updated = plan()
        updated.priorities = priorities
        applyRemote(updated)
    }

    /// AppModel calls this after every mutation of today's plan; remote applies are guarded internally.
    func planChanged(from old: DayPlan, to new: DayPlan) {
        guard !isApplyingRemote, isConnected(), settings().googleTasksSyncEnabled else { return }
        let diff = GoogleTaskMerge.diff(from: old.priorities, to: new.priorities)
        guard !diff.isEmpty else { return }
        Task { await push(diff) }
    }

    private func push(_ diff: PlanDiff) async {
        do {
            for priority in diff.inserts {
                let inserted = try await api.insertTask(title: priority.title, due: dueStamp())
                var updated = plan()
                if let index = updated.priorities.firstIndex(where: { $0.id == priority.id }) {
                    updated.priorities[index].googleTaskID = inserted.id
                    applyRemote(updated)
                }
            }
            for id in diff.completes { _ = try await api.patchTask(id: id, title: nil, status: "completed") }
            for id in diff.reopens { _ = try await api.patchTask(id: id, title: nil, status: "needsAction") }
            for id in diff.deletes { try await api.deleteTask(id: id) }
            for retitle in diff.retitles { _ = try await api.patchTask(id: retitle.id, title: retitle.title, status: nil) }
            lastCycleFailed = false
        } catch GoogleAuthError.revoked {
            // Quiet, as in syncNow.
        } catch {
            report(error)
        }
    }

    /// AppModel calls this for every finalized session; eligibility is checked here.
    func sessionEnded(_ session: Session) {
        guard isConnected(), settings().googleSessionLogEnabled, Self.shouldLog(session) else { return }
        pendingSessions.append(session)
        Task { await syncNow() }
    }

    private func pushPendingSessions() async throws {
        guard !pendingSessions.isEmpty else { return }
        let calendarID = try await tofuCalendarID()
        while let session = pendingSessions.first {
            try await api.insertEvent(calendarID: calendarID,
                                      summary: Self.eventSummary(for: session),
                                      description: Self.eventDescription(for: session),
                                      start: session.start, end: session.end ?? now())
            pendingSessions.removeFirst()
        }
    }

    /// The cached "Tofu" calendar id, found by summary or created on first use (spec §4).
    private func tofuCalendarID() async throws -> String {
        if let cached = settings().googleCalendarID { return cached }
        let calendars = try await api.listCalendars()
        let id: String
        if let existing = calendars.first(where: { $0.summary == "Tofu" }) { id = existing.id }
        else { id = try await api.insertCalendar(summary: "Tofu").id }
        saveCalendarID(id)
        return id
    }

    private func pullEvents() async throws {
        let calendars = try await api.listCalendars()
        let tofuID = settings().googleCalendarID
        // Calendar days are midnight-to-midnight local (spec §4), unlike DayKey's 4 AM window.
        let dayStart = Calendar.current.startOfDay(for: now())
        let dayEnd = dayStart.addingTimeInterval(86_400)
        var all: [GoogleEvent] = []
        for calendar in calendars where calendar.selected == true && calendar.id != tofuID {
            all.append(contentsOf: try await api.listEvents(calendarID: calendar.id, from: dayStart, to: dayEnd))
        }
        todayEvents = all.sorted { ($0.start.parsed ?? dayStart) < ($1.start.parsed ?? dayStart) }
    }

    /// Completed sessions, or bailed ones of at least 5 minutes; never demo, interrupted or unfinished.
    nonisolated static func shouldLog(_ session: Session) -> Bool {
        guard !session.isDemo, session.end != nil else { return false }
        switch session.outcome {
        case .completed: return true
        case .bailed: return session.duration >= 300
        default: return false
        }
    }

    /// Calendar event title for a session, e.g. "Focus: CS128".
    nonisolated static func eventSummary(for session: Session) -> String { "Focus: \(session.subjectName)" }

    /// Calendar event body summarizing goal, outcome and distractions.
    nonisolated static func eventDescription(for session: Session) -> String {
        var parts: [String] = []
        if let goal = session.mode.goalMinutes { parts.append("\(goal) min goal") } else { parts.append("open session") }
        parts.append(session.outcome == .completed ? "completed" : "bailed")
        if session.blockedAttempts > 0 { parts.append("\(session.blockedAttempts) blocked attempts") }
        if session.closedTabs > 0 { parts.append("\(session.closedTabs) tabs closed") }
        return parts.joined(separator: " · ")
    }
}
