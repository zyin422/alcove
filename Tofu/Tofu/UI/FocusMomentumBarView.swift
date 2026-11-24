import SwiftUI

/// Compact, factual 7-day focus momentum bar shown at the top of TodayView.
/// Displays daily focus bars, current streak, and total weekly hours. Zero arbitrary gamification.
struct FocusMomentumBarView: View {
    let summary: FocusMomentumSummary
    let selectedDayKey: String
    var onSelectDay: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(summary.currentStreak > 0 ? Theme.amber : Color.secondary.opacity(0.6))
                        .font(.system(size: 13))

                    Text(summary.currentStreak > 0 ? "\(summary.currentStreak)-day streak" : "Start your streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.indigo)
                    Text("\(summary.totalWeekHoursFormatted) this week")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
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
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(slice.isToday ? Theme.indigo : Color.primary.opacity(0.4))
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
                                    .stroke(isSelected ? Theme.indigo : Color.clear, lineWidth: 1.5)
                            )

                            Text(slice.dayLabel)
                                .font(.system(size: 10, weight: slice.isToday ? .bold : .medium))
                                .foregroundStyle(slice.isToday ? Theme.indigo : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tooltip(for: slice))
                }
            }
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
