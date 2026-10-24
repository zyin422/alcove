import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers
import os

/// Stats screen (spec §10): range toggle, stacked bar chart, summary cards and per-subject breakdown.
struct StatsView: View {
    let model: AppModel
    @State private var range: StatsRange = .day

    var body: some View {
        let sessions = model.data.sessions
        let stats = model.currentStats
        PageScrollView { page in
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Stats").font(Theme.titleFont)
                    Spacer()
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Menu {
                        ForEach(SessionExport.Format.allCases) { format in
                            Button("Export as \(format.title)…") { export(sessions, as: format) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(SessionExport.exportable(sessions).isEmpty)
                    .help("Export your sessions as CSV or JSON")
                    .accessibilityLabel("Export sessions")
                }
                if StatsFormatting.hasTrackedSessions(sessions) {
                    let limit = StatsFormatting.topSubjectLimit(for: sessions, shades: Theme.grays.count)
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(StatsFormatting.rangeCaption(range)).font(Theme.captionFont).foregroundStyle(.secondary)
                        StatsStackedChart(buckets: stats.buckets(sessions, range: range, topSubjects: limit),
                                          maxLabels: StatsFormatting.maxAxisLabels(range),
                                          height: Self.chartHeight(visibleHeight: page.visibleHeight))
                    }
                    StatsSummaryGrid(summary: stats.summary(sessions))
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("By subject").font(Theme.captionFont).foregroundStyle(.secondary)
                        StatsSubjectBreakdown(shares: stats.shares(sessions))
                    }
                } else {
                    Text(StatsFormatting.emptyMessage)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .navigationTitle("Stats")
    }

    /// The chart grows with the window: about a third of the visible height, between 220 and 420 pt.
    static func chartHeight(visibleHeight: CGFloat) -> CGFloat {
        min(max(visibleHeight * 0.36, 220), 420).rounded()
    }

    /// Asks where to save, then writes every finished, non-demo session. A failed write is shown as a toast.
    private func export(_ sessions: [Session], as format: SessionExport.Format) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SessionExport.fileName(format: format)
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionExport.data(sessions, format: format).write(to: url, options: .atomic)
            Log.storage.info("Exported \(SessionExport.exportable(sessions).count, privacy: .public) sessions as \(format.rawValue, privacy: .public)")
        } catch {
            Log.storage.error("Export failed: \(error.localizedDescription, privacy: .public)")
            ToastCenter.shared.show("Couldn't export: \(error.localizedDescription)")
        }
    }
}

/// Adaptive card grid for the summary cards: as many columns as fit, so a wide window shows them in one or two rows.
private let statsGridColumns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.m, alignment: .top)]

/// X axis with at most `maxLabels` untruncated bucket labels (the newest always shown).
private func bucketAxis(_ buckets: [StatsBucket], maxLabels: Int) -> some AxisContent {
    AxisMarks(values: StatsFormatting.axisLabels(buckets.map(\.label), maxCount: maxLabels)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(collisionResolution: .disabled) {
            Text(value.as(String.self) ?? "").fixedSize()
        }
    }
}

/// Bars of minutes per period, stacked by subject, one gray per subject ("Other" lightest).
private struct StatsStackedChart: View {
    let buckets: [StatsBucket]
    let maxLabels: Int
    var height: CGFloat = 260

    var body: some View {
        let subjects = StatsFormatting.chartSubjects(buckets)
        Chart {
            ForEach(buckets) { bucket in
                ForEach(subjects, id: \.self) { subject in
                    if let minutes = bucket.minutesBySubject[subject], minutes > 0 {
                        BarMark(x: .value("Period", bucket.label), y: .value("Minutes", minutes))
                            .foregroundStyle(by: .value("Subject", subject))
                    }
                }
            }
        }
        .chartXScale(domain: buckets.map(\.label))
        .chartXAxis { bucketAxis(buckets, maxLabels: maxLabels) }
        .chartForegroundStyleScale(domain: subjects, range: subjects.indices.map(Theme.gray(at:)))
        .chartYAxisLabel("min")
        .chartLegend(position: .top, alignment: .leading)
        .overlay {
            if subjects.isEmpty {
                Text("No time tracked in this range").foregroundStyle(.secondary)
            }
        }
        .frame(height: height)
    }
}

/// The ten summary cards from spec §10.
private struct StatsSummaryGrid: View {
    let summary: StatsSummary

    var body: some View {
        LazyVGrid(columns: statsGridColumns, alignment: .leading, spacing: Theme.Space.m) {
            StatCard(title: "Today", value: TimeFormat.short(summary.today))
            StatCard(title: "This week", value: TimeFormat.short(summary.thisWeek))
            StatCard(title: "Current streak", value: StatsFormatting.streak(summary.currentStreak))
            StatCard(title: "Longest streak", value: StatsFormatting.streak(summary.longestStreak))
            StatCard(title: "Sessions", value: "\(summary.sessionCount)")
            StatCard(title: "Average", value: TimeFormat.short(summary.average))
            StatCard(title: "Longest", value: TimeFormat.short(summary.longest))
            StatCard(title: "Apps blocked", value: "\(summary.blockedAttempts)")
            StatCard(title: "Tabs closed", value: "\(summary.closedTabs)")
            StatCard(title: "Bails", value: "\(summary.bails)")
        }
    }
}

/// One row per subject: name, proportional bar, total time, percent. Sorted by StatsEngine.shares.
private struct StatsSubjectBreakdown: View {
    let shares: [SubjectShare]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(shares) { share in
                HStack(spacing: Theme.Space.m) {
                    Text(share.name)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    StatsShareBar(fraction: share.fraction)
                    Text(TimeFormat.short(share.seconds))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                    Text(StatsFormatting.percent(share.fraction))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

/// Horizontal bar filled to `fraction` of the available width.
private struct StatsShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 2).fill(Color.primary)
                    .frame(width: proxy.size.width * StatsFormatting.clampedFraction(fraction))
            }
        }
        .frame(height: 8)
    }
}
