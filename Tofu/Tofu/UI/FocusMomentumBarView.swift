import SwiftUI

/// Compact, factual 7-day focus momentum bar shown at the top of TodayView.
/// Displays daily focus bars, current streak, and total weekly hours. Zero arbitrary gamification.
struct FocusMomentumBarView: View {
    let summary: FocusMomentumSummary
    let selectedDayKey: String
    var targetMinutes: Int = 240
    var onSelectDay: ((String) -> Void)?
    var onUpdateTarget: ((Int) -> Void)?

    private var todaySlice: DailyFocusSlice? {
        summary.slices.first(where: \.isToday)
    }

    private var targetSeconds: TimeInterval {
        TimeInterval(targetMinutes * 60)
    }

    private var isTargetAchieved: Bool {
        guard let today = todaySlice, targetSeconds > 0 else { return false }
        return today.focusSeconds >= targetSeconds
    }

    private var targetProgressFraction: Double {
        guard let today = todaySlice, targetSeconds > 0 else { return 0 }
        return min(1.0, today.focusSeconds / targetSeconds)
    }

    private var targetDeltaLabel: String {
        guard let today = todaySlice else { return "" }
        if today.focusSeconds >= targetSeconds {
            let over = Int(today.focusSeconds - targetSeconds) / 60
            return over > 0 ? "Goal crushed (+ \(over)m over target)" : "Daily goal achieved (100%)"
        } else {
            let remaining = Int(targetSeconds - today.focusSeconds) / 60
            let hrs = remaining / 60
            let mins = remaining % 60
            let remString = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
            let pct = Int(targetProgressFraction * 100)
            return "\(remString) to \(targetMinutes / 60)h goal (\(pct)%)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: isTargetAchieved ? "star.fill" : (summary.currentStreak > 0 ? "flame.fill" : "flame"))
                        .foregroundStyle(isTargetAchieved ? Theme.emerald : (summary.currentStreak > 0 ? Theme.amber : Color.secondary.opacity(0.6)))
                        .font(.system(size: 13))

                    Text(summary.currentStreak > 0 ? "\(summary.currentStreak)-day streak" : "Start your streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    if isTargetAchieved {
                        Text("🎯 GOAL CRUSHED")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Theme.emerald)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.emerald.opacity(0.12)))
                    }
                }

                Spacer()

                HStack(spacing: Theme.Space.s) {
                    if onUpdateTarget != nil {
                        Menu {
                            Button("1 hour (60m)") { onUpdateTarget?(60) }
                            Button("2 hours (120m)") { onUpdateTarget?(120) }
                            Button("3 hours (180m)") { onUpdateTarget?(180) }
                            Button("4 hours (240m)") { onUpdateTarget?(240) }
                            Button("5 hours (300m)") { onUpdateTarget?(300) }
                            Button("6 hours (360m)") { onUpdateTarget?(360) }
                            Button("8 hours (480m)") { onUpdateTarget?(480) }
                        } label: {
                            HStack(spacing: 3) {
                                Text("\(targetMinutes / 60)h target")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.indigo)
                        Text("\(summary.totalWeekHoursFormatted) this week")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach(summary.slices) { slice in
                    let isSelected = (slice.dayKey == selectedDayKey)
                    let maxSeconds = max(3600 * 2, summary.bestDaySeconds) // Minimum reference scale of 2h
                    let fraction = maxSeconds > 0 ? min(1.0, slice.focusSeconds / maxSeconds) : 0

                    Button {
                        onSelectDay?(slice.dayKey)
                    } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                // Background track
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 22, height: 38)

                                // Filled focus bar
                                if slice.focusSeconds > 0 {
                                    let barHeight = max(4.0, CGFloat(fraction) * 38.0)
                                    let barColor: Color = slice.isToday ? (isTargetAchieved ? Theme.emerald : Theme.indigo) : Color.primary.opacity(0.4)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: 22, height: barHeight)
                                } else {
                                    Circle()
                                        .fill(Color.primary.opacity(0.12))
                                        .frame(width: 4, height: 4)
                                        .padding(.bottom, 4)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? (slice.isToday && isTargetAchieved ? Theme.emerald : Theme.indigo) : Color.clear, lineWidth: 1.5)
                            )

                            Text(slice.dayLabel)
                                .font(.system(size: 10, weight: slice.isToday ? .bold : .medium))
                                .foregroundStyle(slice.isToday ? (isTargetAchieved ? Theme.emerald : Theme.indigo) : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tooltip(for: slice))
                }
            }

            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(isTargetAchieved ? Theme.emerald : Theme.indigo)
                            .frame(width: max(4, geo.size.width * CGFloat(targetProgressFraction)), height: 4)
                    }
                }
                .frame(height: 4)

                Text(targetDeltaLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isTargetAchieved ? Theme.emerald : .secondary)
                    .lineLimit(1)
            }
            .padding(.top, 2)
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func tooltip(for slice: DailyFocusSlice) -> String {
        let name = slice.isToday ? "Today" : slice.dayKey
        if slice.focusSeconds == 0 {
            return "\(name): No focus time"
        }
        let dur = TimeFormat.short(slice.focusSeconds)
        let sessions = slice.sessionCount == 1 ? "1 session" : "\(slice.sessionCount) sessions"
        return "\(name): \(dur) (\(sessions))"
    }
}
