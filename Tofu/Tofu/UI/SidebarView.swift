import SwiftUI

/// Arc-style sidebar drawn on the tinted window chrome: a top bar beside the traffic lights (hide sidebar),
/// a read-only summary pill, favorite tiles (Today, Stats, Settings), then the subjects as rounded rows with
/// their total time and a "New Subject" row. An update card (when Sparkle found one) sits at the bottom.
/// Right-click deletes a subject.
struct SidebarView: View {
    @Bindable var model: AppModel
    let palette: SidebarPalette
    let dark: Bool
    let onHide: () -> Void
    let onAddSubject: () -> Void
    @State private var subjectToDelete: Subject?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            summaryPill
            favorites
            subjectsHeader
            ScrollView {
                VStack(spacing: 1) {
                    if model.data.subjects.isEmpty {
                        Text("No subjects yet. Add one to lock in.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondaryColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, Theme.Space.s)
                    }
                    ForEach(model.data.subjects) { subject in
                        SubjectRow(subject: subject,
                                   totalTime: totalTime(of: subject.id),
                                   isSelected: model.selection == .subject(subject.id),
                                   palette: palette, dark: dark) {
                            model.selection = .subject(subject.id)
                        }
                        .contextMenu {
                            Button("Delete “\(subject.name)”…") { subjectToDelete = subject }
                        }
                    }
                    newSubjectRow
                }
                .padding(.bottom, Theme.Space.m)
            }
            .scrollIndicators(.never)

            if let version = model.updates.availableVersion {
                UpdateCard(version: version,
                           onUpdate: { model.updates.checkNow() },
                           onDismiss: { model.updates.dismiss() })
                    .foregroundStyle(Color.primary)
                    .padding(.bottom, Theme.Space.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, Theme.Space.s)
        .foregroundStyle(palette.foregroundColor)
        .animation(.spring(duration: 0.35), value: model.updates.availableVersion)
        .confirmationDialog(
            "Delete “\(subjectToDelete?.name ?? "")”?",
            isPresented: Binding(get: { subjectToDelete != nil },
                                 set: { if !$0 { subjectToDelete = nil } }),
            titleVisibility: .visible,
            presenting: subjectToDelete
        ) { subject in
            Button("Delete") { model.deleteSubject(id: subject.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its past sessions stay in your stats.")
        }
    }

    // MARK: Top

    /// Room for the traffic lights, then the hide-sidebar button, centered on the lights' row. Empty space drags
    /// the window, as a title bar would. Subjects are added from the "New Subject" row (⌘N), not from here.
    private var topBar: some View {
        HStack(spacing: 2) {
            Spacer()
            SidebarIconButton(systemImage: "sidebar.left", help: "Hide sidebar (⌘S)",
                              palette: palette, dark: dark, action: onHide)
        }
        .padding(.leading, 70)
        .frame(height: 30)
        .padding(.bottom, 6)
        .background(WindowDragArea())
    }

    /// Today's focus time and the streak, in the spot where Arc shows the address. A readout only: the Stats
    /// tile below is the way into Stats.
    private var summaryPill: some View {
        let summary = StatsEngine(now: max(model.engine.now, Date())).summary(model.data.sessions)
        let streak = summary.currentStreak == 1 ? "1-day streak" : "\(summary.currentStreak)-day streak"
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "timer").font(.system(size: 12, weight: .semibold))
            Text("Today \(TimeFormat.short(summary.today))").monospacedDigit()
            Text("·")
            Text(streak).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.secondaryColor)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SidebarFill.tile(dark: dark)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today \(TimeFormat.short(summary.today)), \(streak)")
    }

    /// Big tiles for the places that are not subjects, like Arc's Favorites.
    private var favorites: some View {
        HStack(spacing: Theme.Space.s) {
            FavoriteTile(title: "Today", systemImage: "checklist", isSelected: model.selection == .today,
                         palette: palette, dark: dark) { model.selection = .today }
            FavoriteTile(title: "Stats", systemImage: "chart.bar", isSelected: model.selection == .stats,
                         palette: palette, dark: dark) { model.selection = .stats }
            FavoriteTile(title: "Settings", systemImage: "gearshape", isSelected: model.selection == .settings,
                         palette: palette, dark: dark) { model.selection = .settings }
        }
        .padding(.top, 12)
        .padding(.bottom, Theme.Space.xs)
    }

    private var subjectsHeader: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "books.vertical").font(.system(size: 13))
            Text("Subjects").font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .padding(.top, Theme.Space.s)
    }

    private var newSubjectRow: some View {
        Button(action: onAddSubject) {
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 18)
                Text("New Subject")
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(palette.secondaryColor)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(dark: dark))
        .help("Add subject (⌘N)")
    }

    /// Total time of the subject's finished sessions.
    private func totalTime(of subjectID: UUID) -> TimeInterval {
        model.data.sessions
            .filter { $0.subjectID == subjectID && $0.end != nil }
            .reduce(0) { $0 + $1.duration }
    }
}

/// One subject: a letter badge, the name, and its total time. Lifted when selected, washed on hover.
private struct SubjectRow: View {
    let subject: Subject
    let totalTime: TimeInterval
    let isSelected: Bool
    let palette: SidebarPalette
    let dark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(String(subject.name.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(SidebarPalette.color(.init(h: SidebarPalette.hue(for: subject.id), s: 55,
                                                         l: dark ? 45 : 58))))
                    .foregroundStyle(.white)
                Text(subject.name).lineLimit(1)
                Spacer(minLength: Theme.Space.xs)
                Text(TimeFormat.short(totalTime))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryColor)
            }
            .font(.system(size: 13))
            .padding(.leading, 10)
            .padding(.trailing, Theme.Space.s)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(dark: dark, isSelected: isSelected))
        .accessibilityLabel("\(subject.name), \(TimeFormat.short(totalTime)) total")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Rounded row background: selected pill with a soft shadow, hover wash, a darker wash while pressed.
private struct SidebarRowButtonStyle: ButtonStyle {
    let dark: Bool
    var isSelected = false
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? SidebarFill.selected(dark: dark)
                          : (isHovering || configuration.isPressed) ? SidebarFill.hover(dark: dark) : .clear)
                    .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: 1.5, y: 1)
            )
            .onHover { isHovering = $0 }
    }
}

/// A favorite: a 48 pt tile with an icon; the title shows on hover and to VoiceOver.
private struct FavoriteTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let palette: SidebarPalette
    let dark: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? SidebarFill.selected(dark: dark)
                              : isHovering ? SidebarFill.tileHover(dark: dark) : SidebarFill.tile(dark: dark))
                        .shadow(color: .black.opacity(isSelected ? 0.2 : 0), radius: 2, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 28 pt square icon button for the sidebar's top bar.
struct SidebarIconButton: View {
    let systemImage: String
    let help: String
    let palette: SidebarPalette
    let dark: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isHovering ? palette.foregroundColor : palette.secondaryColor)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? SidebarFill.hover(dark: dark) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
