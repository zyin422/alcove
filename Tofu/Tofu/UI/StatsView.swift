import Charts
import SwiftUI

/// Stats screen. Day is one day's subjects. Week and month are one period at a time. Year is that year's months.
struct StatsView: View {
    let model: AppModel
    @State private var span: StatsSpan = .day
    @State private var anchor = Date()

    var body: some View {
        let sessions = model.data.sessions
        let today = max(model.engine.now, Date())
        let stats = StatsEngine(now: today)
        let latest = stats.startOf(span, containing: today)
        let shown = min(stats.startOf(span, containing: anchor), latest)
        let period = stats.matching(sessions, span: span, containing: shown)
        let summary = stats.summary(period)
        let overallSummary = stats.summary(sessions)
        let comparison = stats.periodComparison(sessions, span: span, containing: shown)
        let heatmapColumns = stats.consistencyHeatmap(sessions: sessions, weeks: 12)
        let shares = stats.shares(period)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                tabHeader(summary: summary, shares: shares, comparison: comparison, heading: stats.heading(span, containing: shown))
                        if StatsFormatting.hasTrackedSessions(sessions) {
                            periodControls(stats: stats, sessions: sessions, shown: shown, latest: latest)
                            StatsSummaryGrid(summary: summary, overallSummary: overallSummary, comparison: comparison, subjectCount: shares.count)
                            if span == .day {
                                if !period.isEmpty {
                                    DayChronologicalTimeline(sessions: period, day: shown, color: color(for:))
                                }
                                dayDetail(StatsFormatting.subjectBlocks(period))
                            } else {
                                periodChart(stats: stats, sessions: period, shown: shown)
                                if !shares.isEmpty {
                                    StatsSubjectBreakdown(
                                        shares: shares,
                                        color: color(for:),
                                        subjectIDForName: { name in
                                            model.data.subjects.first(where: { $0.name == name })?.id
                                        },
                                        onSelectSubject: { id in
                                            model.selection = .subject(id)
                                        }
                                    )
                                }
                                TimeBlockList(blocks: StatsFormatting.timeBlocks(period),
                                              onUpdateNotes: { model.updateSessionNotes(id: $0, notes: $1) },
                                              onDelete: { model.deleteSession(id: $0) })
                            }
                            FocusConsistencyHeatmap(
                                columns: heatmapColumns,
                                selectedDay: shown,
                                onSelectDay: { date in
                                    span = .day
                                    anchor = min(date, latest)
                                }
                            )
                            FocusTelemetrySection(stats: stats, sessions: period)
                        } else {
                            Text(StatsFormatting.emptyMessage)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Stats")
        }

    private func tabHeader(summary: StatsSummary, shares: [SubjectShare], comparison: PeriodComparison, heading: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Stats").font(Theme.titleFont)
            Spacer()

            Button {
                copyRecap(summary: summary, shares: shares, comparison: comparison, span: span, heading: heading)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Recap")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)

            Picker("Range", selection: $span) {
                ForEach(StatsSpan.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
        }
    }

    /// Chevrons and a horizontal strip. On Day, the arrows move a week and each day is its own button.
    private func periodControls(stats: StatsEngine, sessions: [Session], shown: Date, latest: Date) -> some View {
        let marks = stats.timeline(sessions, span: span)
        let earliest = marks.first ?? shown
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            if span == .day {
                HStack {
                    Text(stats.monthDay(shown))
                        .font(.title3)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    Button("Today") { anchor = latest }
                        .buttonStyle(.borderless)
                        .disabled(shown >= latest)
                }
                HStack(spacing: Theme.Space.s) {
                    weekArrow(systemName: "chevron.left", enabled: canStepWeek(stats, shown: shown, earliest: earliest, latest: latest, by: -1)) {
                        anchor = stats.shift(shown, span: .day, by: -7)
                    }
                    dayStrip(stats: stats, shown: shown, latest: latest)
                    weekArrow(systemName: "chevron.right", enabled: canStepWeek(stats, shown: shown, earliest: earliest, latest: latest, by: 1)) {
                        anchor = stats.shift(shown, span: .day, by: 7)
                    }
                }
            } else {
                HStack {
                    weekArrow(systemName: "chevron.left", enabled: shown > earliest) {
                        anchor = stats.shift(shown, span: span, by: -1)
                    }
                    Spacer()
                    Text(stats.heading(span, containing: shown))
                        .font(.title3)
                    Spacer()
                    weekArrow(systemName: "chevron.right", enabled: shown < latest) {
                        anchor = stats.shift(shown, span: span, by: 1)
                    }
                }
                periodStrip(stats: stats, marks: marks, shown: shown)
            }
        }
    }

    private func canStepWeek(_ stats: StatsEngine, shown: Date, earliest: Date, latest: Date, by weeks: Int) -> Bool {
        let next = stats.shift(shown, span: .day, by: weeks * 7)
        if weeks > 0 { return next <= latest }
        return stats.startOf(.week, containing: next) >= stats.startOf(.week, containing: earliest)
    }

    private func weekArrow(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 36, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private func periodStrip(stats: StatsEngine, marks: [Date], shown: Date) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(marks, id: \.self) { start in
                        Button {
                            anchor = start
                        } label: {
                            Text(stats.chipTitle(span, containing: start))
                                .font(.caption)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, Theme.Space.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(start == shown ? Color.primary.opacity(0.12) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(start == shown ? 0.45 : 0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(start)
                    }
                }
                .padding(.vertical, 1)
            }
            .onAppear { proxy.scrollTo(shown, anchor: .center) }
            .onChange(of: shown) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// Seven day buttons for the week on screen. The whole cell is the hit target.
    private func dayStrip(stats: StatsEngine, shown: Date, latest: Date) -> some View {
        let weekStart = stats.startOf(.week, containing: shown)
        let days = (0..<7).map { stats.shift(weekStart, span: .day, by: $0) }
        return HStack(spacing: Theme.Space.xs) {
            ForEach(days, id: \.self) { day in
                let future = day > latest
                let selected = day == shown
                Button {
                    anchor = day
                } label: {
                    VStack(spacing: 4) {
                        Text(stats.monthDay(day))
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(selected ? 0.55 : 0.12), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(future)
                .opacity(future ? 0.35 : 1)
            }
        }
    }

    /// One card per subject: hours, share, and the session counts for that day.
    @ViewBuilder private func dayDetail(_ subjects: [SubjectBlocks]) -> some View {
        if subjects.isEmpty {
            Text("No time tracked this day")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 88)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(subjects) { subject in
                    DaySubjectCard(subject: subject, color: color(for: subject.name),
                                   onUpdateNotes: { model.updateSessionNotes(id: $0, notes: $1) },
                                   onDelete: { model.deleteSession(id: $0) })
                }
            }
        }
    }

    private func periodChart(stats: StatsEngine, sessions: [Session], shown: Date) -> some View {
        let buckets = stats.periodBuckets(sessions, span: span, containing: shown, topSubjects: 16)
        return StatsStackedChart(buckets: buckets, maxLabels: axisCount(span, buckets: buckets.count),
                                  colors: colors(for: StatsFormatting.chartSubjects(buckets)))
    }

    private func color(for name: String) -> Color {
        if name == StatsEngine.otherLabel { return Color.primary.opacity(0.28) }
        if let subject = model.data.subjects.first(where: { $0.name == name }) {
            return Theme.subjectColor(subject.colorHex)
        }
        return Theme.subjectColor(SubjectColor.hex(for: name))
    }

    private func colors(for names: [String]) -> [Color] {
        names.map { color(for: $0) }
    }

    /// Week shows every day. Month keeps enough day numbers to stay readable. Year shows every month.
    private func axisCount(_ span: StatsSpan, buckets: Int) -> Int {
        span == .month ? min(buckets, 8) : buckets
    }

    private func copyRecap(summary: StatsSummary, shares: [SubjectShare], comparison: PeriodComparison, span: StatsSpan, heading: String) {
        let text = StatsFormatting.markdownRecap(
            summary: summary,
            shares: shares,
            comparison: comparison,
            span: span,
            heading: heading
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastCenter.shared.show("Recap copied to clipboard")
    }
}

/// One subject on the selected day: hours, share, and four counts.
private struct DaySubjectCard: View {
    let subject: SubjectBlocks
    let color: Color
    let onUpdateNotes: (UUID, String?) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(subject.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Text(TimeFormat.short(subject.seconds))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                Text(StatsFormatting.percent(subject.fraction))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            StatsShareBar(fraction: subject.fraction, color: color)
            HStack(spacing: Theme.Space.s) {
                dayStat("Sessions", "\(subject.sessionCount)")
                dayStat("Average", TimeFormat.short(subject.average))
                dayStat("Longest", TimeFormat.short(subject.longest))
                dayStat("Started", started)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(subject.blocks) { block in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(block.start.formatted(.dateTime.hour().minute()))
                                .foregroundStyle(.secondary)
                            Spacer()
                            TimeBlockNoteButton(initialNote: block.notes) { updated in
                                onUpdateNotes(block.id, updated)
                            }
                            Text(TimeFormat.short(block.seconds))
                                .monospacedDigit()
                            SessionRemoveButton { onDelete(block.id) }
                        }
                        if let notes = block.notes, !notes.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "note.text").font(.system(size: 8))
                                Text(notes).font(.caption2).lineLimit(2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var started: String {
        subject.blocks.first?.start.formatted(.dateTime.hour().minute()) ?? "—"
    }

    private func dayStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Visual 24-hour horizontal timeline showing when focus sessions occurred during the day.
private struct DayChronologicalTimeline: View {
    let sessions: [Session]
    let day: Date
    let color: (String) -> Color
    @State private var hoveredSession: Session?

    private static let hourMarkers = [0, 4, 8, 12, 16, 20, 24]

    var body: some View {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Day Timeline")
                    .font(.headline)
                Spacer()
                if let hovered = hoveredSession {
                    Text("\(hovered.subjectName) · \(hovered.start.formatted(.dateTime.hour().minute())) - \((hovered.end ?? hovered.lastHeartbeat).formatted(.dateTime.hour().minute())) (\(TimeFormat.short(hovered.duration)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("24-hour distribution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 1))

                    ForEach(sessions) { session in
                        let startSec = max(0, min(86400, session.start.timeIntervalSince(startOfDay)))
                        let durSec = max(60, session.duration)
                        let x = (startSec / 86400.0) * width
                        let w = max(4.0, (durSec / 86400.0) * width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(session.subjectName))
                            .frame(width: min(w, max(0, width - x)), height: 20)
                            .offset(x: x, y: 0)
                            .onHover { isHovered in
                                hoveredSession = isHovered ? session : nil
                            }
                    }
                }
            }
            .frame(height: 24)

            HStack {
                ForEach(Self.hourMarkers, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if hour != Self.hourMarkers.last {
                        Spacer()
                    }
                }
            }
        }
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return "12 AM"
        case 12: return "12 PM"
        case let h where h < 12: return "\(h) AM"
        default: return "\(hour - 12) PM"
        }
    }
}

/// Finished work blocks in the period on screen, newest first.
private struct TimeBlockList: View {
    let blocks: [TimeBlock]
    let onUpdateNotes: (UUID, String?) -> Void
    let onDelete: (UUID) -> Void

    private var maxSeconds: TimeInterval {
        max(60, blocks.map(\.seconds).max() ?? 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Time blocks").font(Theme.captionFont).foregroundStyle(.secondary)
                Spacer()
                if !blocks.isEmpty {
                    Text("\(blocks.count) blocks · \(TimeFormat.short(blocks.reduce(0) { $0 + $1.seconds })) total")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if blocks.isEmpty {
                Text("No time blocks in this period")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.Space.s)
            } else {
                VStack(spacing: 2) {
                    ForEach(blocks) { block in
                        let color = Theme.subjectColor(SubjectColor.hex(for: block.subjectName))
                        let barFraction = min(1.0, max(0.08, block.seconds / maxSeconds))
                        HStack(spacing: Theme.Space.m) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.subjectName).lineLimit(1).font(.body.weight(.medium))
                                Text(block.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let notes = block.notes, !notes.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "note.text").font(.system(size: 8))
                                        Text(notes).font(.caption2).lineLimit(2)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: Theme.Space.s)

                            TimeBlockNoteButton(initialNote: block.notes) { updated in
                                onUpdateNotes(block.id, updated)
                            }

                            // Visual duration bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.35))
                                .frame(width: 80 * barFraction, height: 6)

                            Text(TimeFormat.short(block.seconds))
                                .font(.body.monospacedDigit())
                            SessionRemoveButton { onDelete(block.id) }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, Theme.Space.s)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.02)))
                    }
                }
            }
        }
    }
}

/// Popover editor to add or update reflection notes on any historical session block.
private struct TimeBlockNoteButton: View {
    let initialNote: String?
    let onSave: (String?) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        Button {
            draft = initialNote ?? ""
            isEditing = true
        } label: {
            Image(systemName: (initialNote?.isEmpty == false) ? "square.and.pencil" : "note.text.badge.plus")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle((initialNote?.isEmpty == false) ? Theme.indigo : .secondary)
        .help((initialNote?.isEmpty == false) ? "Edit session note" : "Add session note")
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Session note")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                TextField("What did you accomplish or notice?", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit {
                        onSave(draft)
                        isEditing = false
                    }
                HStack {
                    if initialNote?.isEmpty == false {
                        Button("Clear") {
                            onSave(nil)
                            isEditing = false
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") {
                        onSave(draft)
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(Theme.Space.m)
        }
    }
}

/// Drops one finished block from the stats list.
private struct SessionRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Remove")
    }
}

/// Four columns, so eight cards stay in two even rows.
private let statsGridColumns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m), count: 4)

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
    let colors: [Color]

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
        .chartForegroundStyleScale(domain: subjects, range: colors)
        .chartYAxisLabel("min")
        .chartLegend(position: .top, alignment: .leading)
        .overlay {
            if subjects.isEmpty {
                Text("No time tracked").foregroundStyle(.secondary)
            }
        }
        .frame(height: 260)
    }
}

/// Summary Bento Grid for the active period, led by Total Focus with period-over-period comparison delta.
private struct StatsSummaryGrid: View {
    let summary: StatsSummary
    let overallSummary: StatsSummary
    let comparison: PeriodComparison
    let subjectCount: Int

    private var scoreTint: Color {
        if summary.focusScore >= 80 { return Theme.emerald }
        if summary.focusScore >= 60 { return Theme.amber }
        return Theme.coral
    }

    private var deltaTint: Color {
        if comparison.deltaSeconds >= 60 { return Theme.emerald }
        if comparison.deltaSeconds <= -60 { return Theme.coral }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(Theme.indigo)
                        Text("TOTAL FOCUS")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(comparison.trendLabel)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(deltaTint.opacity(0.12)))
                            .foregroundStyle(deltaTint)
                    }
                    Text(TimeFormat.short(summary.total))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(summary.sessionCount) sessions · \(subjectCount) subjects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.indigo.opacity(0.22), lineWidth: 1)
                        )
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bolt.shield.fill")
                            .foregroundStyle(Theme.emerald)
                        Text("DEEP WORK (≥25m)")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let deepPct = summary.total > 0 ? Int(((summary.deepWorkSeconds / summary.total) * 100).rounded()) : 0
                        Text("\(deepPct)% of focus")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.emerald)
                    }
                    Text(TimeFormat.short(summary.deepWorkSeconds))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Avg block \(TimeFormat.short(summary.average)) · Longest \(TimeFormat.short(summary.longest))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            LazyVGrid(columns: statsGridColumns, alignment: .leading, spacing: Theme.Space.m) {
                StatCard(title: "Focus Score", value: "\(summary.focusScore)%", tint: scoreTint, icon: "chart.line.uptrend.xyaxis")
                StatCard(title: "Current Streak", value: "\(overallSummary.currentStreak)d", tint: overallSummary.currentStreak > 0 ? Theme.amber : nil, icon: "flame.fill")
                StatCard(title: "Best Streak", value: "\(overallSummary.longestStreak)d", icon: "trophy.fill")
                StatCard(title: "Shield Deflections", value: "\(summary.blockedAttempts + summary.closedTabs)", tint: (summary.blockedAttempts + summary.closedTabs) > 0 ? Theme.rose : nil, icon: "shield.fill")
            }
        }
    }
}

/// One row per subject: name, proportional bar, total time, percent. Sorted by StatsEngine.shares.
private struct StatsSubjectBreakdown: View {
    let shares: [SubjectShare]
    let color: (String) -> Color
    let subjectIDForName: (String) -> UUID?
    let onSelectSubject: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(shares) { share in
                let subjectID = subjectIDForName(share.name)
                let content = VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Space.m) {
                        HStack(spacing: 5) {
                            Circle().fill(color(share.name)).frame(width: 7, height: 7)
                            Text(share.name).lineLimit(1)
                        }
                        .frame(width: 132, alignment: .leading)
                        StatsShareBar(fraction: share.fraction, color: color(share.name))
                        Text(TimeFormat.short(share.seconds))
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                        Text(StatsFormatting.percent(share.fraction))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        if subjectID != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    SubjectStatLine(sessions: share.sessionCount, average: share.average, longest: share.longest)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())

                if let subjectID {
                    Button {
                        onSelectSubject(subjectID)
                    } label: {
                        content
                    }
                    .buttonStyle(.plain)
                    .help("Open \(share.name) setup")
                } else {
                    content
                }
            }
        }
    }
}

/// Interactive 12-week Focus Consistency Heatmap; clicking a day cell jumps straight to that day's Stats view.
private struct FocusConsistencyHeatmap: View {
    let columns: [[ConsistencyHeatmapDay]]
    let selectedDay: Date
    let onSelectDay: (Date) -> Void
    @State private var hoveredDay: ConsistencyHeatmapDay?

    var body: some View {
        let cal = Calendar.current
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3.fill")
                        .foregroundStyle(Theme.indigo)
                    Text("12-Week Consistency Heatmap")
                        .font(.headline)
                }
                Spacer()
                if let hovered = hoveredDay {
                    Text("\(hovered.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(hovered.totalMinutes > 0 ? TimeFormat.short(hovered.totalMinutes * 60) : "0m") (\(hovered.sessionCount) blocks)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("Less").font(.caption2).foregroundStyle(.secondary)
                        ForEach(0..<5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cellColor(level))
                                .frame(width: 10, height: 10)
                        }
                        Text("More").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 5) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 5) {
                        ForEach(week) { day in
                            let isSelected = cal.isDate(day.date, inSameDayAs: selectedDay)
                            Button {
                                onSelectDay(day.date)
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(cellColor(day.intensityLevel))
                                    .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(isSelected ? Theme.amber : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .onHover { inside in
                                hoveredDay = inside ? day : nil
                            }
                            .help("\(day.dayKey): \(Int(day.totalMinutes))m across \(day.sessionCount) blocks")
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func cellColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.05)
        case 1: return Theme.indigo.opacity(0.24)
        case 2: return Theme.indigo.opacity(0.48)
        case 3: return Theme.indigo.opacity(0.75)
        default: return Theme.indigo
        }
    }
}

/// Sessions, average, and longest for one subject in the period on screen.
private struct SubjectStatLine: View {
    let sessions: Int
    let average: TimeInterval
    let longest: TimeInterval

    var body: some View {
        Text(StatsFormatting.subjectLine(sessions: sessions, average: average, longest: longest))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Horizontal bar filled to `fraction` of the available width.
private struct StatsShareBar: View {
    let fraction: Double
    var color: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 2).fill(color)
                    .frame(width: proxy.size.width * StatsFormatting.clampedFraction(fraction))
            }
        }
        .frame(height: 8)
    }
}

/// Industrial telemetry showing Focus Velocity momentum and 24-hour diurnal focus heatmap.
private struct FocusTelemetrySection: View {
    let stats: StatsEngine
    let sessions: [Session]

    var body: some View {
        let velocity = stats.focusVelocity(sessions)
        let distribution = stats.hourlyDistribution(sessions)
        let maxMins = max(1.0, distribution.map(\.totalMinutes).max() ?? 1.0)
        let peakHour = distribution.max { $0.totalMinutes < $1.totalMinutes }

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Focus Velocity & Telemetry")
                .font(.headline)

            HStack(alignment: .top, spacing: Theme.Space.m) {
                // Focus Velocity Score
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Image(systemName: "bolt.batteryblock.fill")
                            .foregroundStyle(Theme.amber)
                        Text("Focus Velocity")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(velocity.rating)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.amber.opacity(0.15)))
                            .foregroundStyle(Theme.amber)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(velocity.score)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("/ 100")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Clean session rate")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(velocity.cleanSessionRate * 100))%")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                        }
                        HStack {
                            Text("Completion integrity")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(velocity.completionRate * 100))%")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )

                // Diurnal Heatmap
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.indigo)
                        Text("Diurnal Focus Distribution (24h)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let peak = peakHour, peak.totalMinutes > 0 {
                            Text("Peak: \(peak.hourLabel)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.indigo.opacity(0.12)))
                                .foregroundStyle(Theme.indigo)
                        }
                    }

                    // 24-hour vertical micro bars
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(distribution) { item in
                            let heightFrac = max(0.08, item.totalMinutes / maxMins)
                            let isPeak = peakHour?.hour == item.hour && item.totalMinutes > 0

                            RoundedRectangle(cornerRadius: 2)
                                .fill(isPeak ? Theme.indigo : (item.totalMinutes > 0 ? Color.primary.opacity(0.35) : Color.primary.opacity(0.08)))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50 * CGFloat(heightFrac))
                                .help("\(item.hourLabel): \(Int(item.totalMinutes))m focus (\(item.sessionCount) blocks)")
                        }
                    }
                    .frame(height: 50, alignment: .bottom)

                    HStack {
                        Text("12 AM")
                        Spacer()
                        Text("6 AM")
                        Spacer()
                        Text("12 PM")
                        Spacer()
                        Text("6 PM")
                        Spacer()
                        Text("11 PM")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
            }
        }
    }
}
