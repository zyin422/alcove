import SwiftUI

/// Visual Knowledge Tech Tree and Subject Mastery Map.
/// Displays progressive skill levels, tier milestones, experience points (XP), and achievement badges.
struct TechTreeView: View {
    let model: AppModel
    @State private var selectedSubjectID: UUID?

    var body: some View {
        let masteries = TechTreeEngine.computeAll(
            subjects: model.data.subjects,
            sessions: model.data.sessions,
            plans: model.data.dayPlans
        )

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                globalMasteryHeader(masteries: masteries)

                if masteries.isEmpty {
                    emptyState
                } else {
                    subjectsGrid(masteries: masteries)
                    badgesSection(masteries: masteries)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Global Overview Header

    private func globalMasteryHeader(masteries: [SubjectMastery]) -> some View {
        let totalXP = masteries.reduce(0) { $0 + $1.xp }
        let totalHours = masteries.reduce(0.0) { $0 + $1.totalHours }
        let totalUnlockedBadges = masteries.reduce(0) { $0 + $1.unlockedBadges.count }
        let maxPossibleBadges = masteries.count * MasteryBadgeID.allCases.count

        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Mastery Map")
                        .font(Theme.titleFont)
                    Text("Track your cumulative depth, tier unlocks, and focus badges.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Companion Metrics Bento Row
            HStack(spacing: Theme.Space.m) {
                statCard(
                    title: "Total Focus",
                    value: String(format: "%.1f hrs", totalHours),
                    icon: "clock.badge.checkmark",
                    color: Theme.indigo
                )
                statCard(
                    title: "Mastery XP",
                    value: "\(totalXP.formatted()) XP",
                    icon: "sparkles",
                    color: Theme.amber
                )
                statCard(
                    title: "Badges Earned",
                    value: "\(totalUnlockedBadges) / \(max(1, maxPossibleBadges))",
                    icon: "rosette",
                    color: Theme.plum
                )
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Subjects Grid

    private func subjectsGrid(masteries: [SubjectMastery]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Subject Skill Trees")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(masteries) { mastery in
                    subjectNodeCard(mastery: mastery)
                }
            }
        }
    }

    private func subjectNodeCard(mastery: SubjectMastery) -> some View {
        let subjectColor = Theme.subjectColor(mastery.subject.colorHex)

        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Card Header
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Circle()
                    .fill(subjectColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: subjectColor.opacity(0.6), radius: 3)

                Text(mastery.subject.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Tier Pill
                Text(mastery.tier.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(subjectColor.opacity(0.15))
                            .overlay(Capsule().stroke(subjectColor.opacity(0.4), lineWidth: 1))
                    )
            }

            // Level & XP
            HStack(spacing: Theme.Space.s) {
                Text("Level \(mastery.level)")
                    .font(.subheadline.weight(.bold))
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(mastery.xp) XP")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f hrs", mastery.totalHours))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }

            // Progress to next tier
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(subjectColor)
                            .frame(width: geo.size.width * CGFloat(mastery.progressToNextTier), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    if let nextTier = mastery.tier.next, let remaining = mastery.secondsToNextTier {
                        Text("\(Int(mastery.progressToNextTier * 100))% to \(nextTier.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f hrs left", remaining / 3600.0))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Maximum Tier Reached")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(subjectColor)
                    }
                }
            }

            // Badges row
            HStack(spacing: 6) {
                ForEach(MasteryBadgeID.allCases) { badgeID in
                    let isUnlocked = mastery.unlockedBadges.contains { $0.id == badgeID }
                    Image(systemName: badgeID.systemImage)
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(isUnlocked ? subjectColor : Color.secondary.opacity(0.3))
                        .background(
                            Circle()
                                .fill(isUnlocked ? subjectColor.opacity(0.12) : Color.primary.opacity(0.03))
                                .overlay(
                                    Circle()
                                        .stroke(isUnlocked ? subjectColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                        )
                        .help("\(badgeID.title): \(badgeID.description) (\(isUnlocked ? "Unlocked" : "Locked"))")
                }
                Spacer()
            }
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Badges Section

    private func badgesSection(masteries: [SubjectMastery]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Achievement Milestones")
                .font(.headline)

            VStack(spacing: Theme.Space.s) {
                ForEach(MasteryBadgeID.allCases) { badgeID in
                    let unlockedCount = masteries.filter { mastery in
                        mastery.unlockedBadges.contains { $0.id == badgeID }
                    }.count

                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: badgeID.systemImage)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(unlockedCount > 0 ? Theme.indigo : Color.secondary.opacity(0.4))
                            .background(
                                Circle()
                                    .fill(unlockedCount > 0 ? Theme.indigo.opacity(0.12) : Color.primary.opacity(0.04))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(badgeID.title)
                                .font(.subheadline.weight(.semibold))
                            Text(badgeID.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if unlockedCount > 0 {
                            Text("\(unlockedCount) / \(masteries.count) subjects")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.indigo)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.indigo.opacity(0.1)))
                        } else {
                            Text("Locked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(Theme.Space.s)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.02))
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "tree")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No subjects yet")
                .font(.headline)
            Text("Add subjects and start focused lock-in blocks to grow your mastery trees.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
