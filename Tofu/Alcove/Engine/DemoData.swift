import Foundation

/// Seeded demo content so the stats screens look full (spec §10 "Demo data").
enum DemoData {
    private static let goalChoices = [25, 50, 90]

    /// CS128 (split) and MATH241 (mainSide) with example sites.
    static func defaultSubjects(now: Date) -> [Subject] {
        [
            Subject(name: "CS128", preset: .split,
                    sites: ["https://cs128.org", "https://prairielearn.org"],
                    extraDomains: ["piazza.com"], createdAt: now),
            Subject(name: "MATH241", preset: .mainSide,
                    sites: ["https://www.desmos.com/calculator"], createdAt: now),
        ]
    }

    /// Deterministic (SplitMix64 seeded) sessions over the last `days` days, all isDemo = true, end set.
    /// Per day (today included): 0-3 non-overlapping sessions starting between 08:00 and 22:00.
    /// 60% goal mode (25/50/90 min): completed at exactly the goal, or (1 in 6) bailed after 15 min..goal-1.
    /// 40% open mode: completed after 15-120 min. Sessions that would end after `now` are dropped.
    /// Same inputs + seed always produce the same sessions (including ids), oldest first.
    static func generate(subjects: [Subject], days: Int = 30, now: Date, calendar: Calendar = .current,
                         seed: UInt64 = 42) -> [Session] {
        guard !subjects.isEmpty, days > 0 else { return [] }
        var rng = SplitMix64(seed: seed)
        let today = calendar.startOfDay(for: now)
        var sessions: [Session] = []

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let count = rng.int(4)                         // 0-3 sessions
            var minuteOfDay = 8 * 60 + rng.int(181)        // first start 08:00-11:00
            for _ in 0..<count {
                guard minuteOfDay <= 22 * 60,
                      let start = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                                                second: 0, of: day)
                else { break }
                let subject = subjects[rng.int(subjects.count)]
                let mode: SessionMode = rng.int(10) < 6
                    ? .goal(minutes: goalChoices[rng.int(goalChoices.count)])
                    : .open
                let bailed = mode.goalMinutes != nil && rng.int(6) == 0
                let minutes: Int
                if let goal = mode.goalMinutes {
                    minutes = bailed ? 15 + rng.int(goal - 15) : goal
                } else {
                    minutes = 15 + rng.int(106)                // 15-120 min
                }
                let attempts = rng.int(7)                      // 0-6
                let tabs = rng.int(5)                          // 0-4
                let id = rng.uuid()
                minuteOfDay += minutes + 30 + rng.int(121)     // 30-150 min break before the next one

                let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                guard end <= now else { continue }
                sessions.append(Session(id: id, subjectID: subject.id, subjectName: subject.name, mode: mode,
                                        start: start, end: end, lastHeartbeat: end,
                                        blockedAttempts: attempts, closedTabs: tabs,
                                        outcome: bailed ? .bailed : .completed, isDemo: true))
            }
        }
        return sessions
    }
}

/// SplitMix64 PRNG: tiny and fully deterministic for a given seed.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Integer in 0..<upperBound (0 when upperBound <= 0).
    mutating func int(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    /// Version-4 UUID built from generator output.
    mutating func uuid() -> UUID {
        let high = next()
        let low = next()
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            b[i] = UInt8(truncatingIfNeeded: high >> (56 - 8 * i))
            b[8 + i] = UInt8(truncatingIfNeeded: low >> (56 - 8 * i))
        }
        b[6] = (b[6] & 0x0F) | 0x40   // version 4
        b[8] = (b[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
