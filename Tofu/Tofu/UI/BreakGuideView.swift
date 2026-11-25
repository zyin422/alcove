import SwiftUI

/// Guided break screen featuring cognitive reset breath pacing, eye strain relief, and ergonomic stretches.
struct BreakGuideView: View {
    let engine: SessionEngine
    @State private var mode: ResetMode = .breathing
    @State private var technique: BreathingTechnique = .box
    @State private var eyeTimerSeconds: Int = 20
    @State private var isEyeTimerRunning = false

    private enum ResetMode: String, CaseIterable, Identifiable {
        case breathing = "Breath Pacer"
        case eyeRelief = "20-20-20 Eye Relief"
        case stretches = "Micro-Stretches"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                breakHeader

                Picker("Reset Mode", selection: $mode) {
                    ForEach(ResetMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                switch mode {
                case .breathing:
                    breathingSection
                case .eyeRelief:
                    eyeReliefSection
                case .stretches:
                    stretchesSection
                }

                Spacer(minLength: Theme.Space.m)
                endBreakButton
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var breakHeader: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack(spacing: 6) {
                Circle().fill(Theme.coral).frame(width: 8, height: 8)
                Text("RESTORATIVE BREAK")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.coral)
                    .tracking(2)
            }

            if let remaining = engine.breakRemaining {
                Text(TimeFormat.clockFull(remaining))
                    .font(Theme.timerFont(size: 40))
                    .foregroundStyle(Theme.coral)
                    .monospacedDigit()
            } else {
                Text("00:00")
                    .font(Theme.timerFont(size: 40))
                    .foregroundStyle(.secondary)
            }

            Text("Step away from the screen, loosen shoulders, and reset cognitive load.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if FocusAudioEngine.shared.isPlaying, let title = FocusAudioEngine.shared.currentTrackTitle {
                HStack(spacing: 6) {
                    let tracks = FocusAudioEngine.shared.availableTrackTitles
                    if tracks.count > 1 && FocusAudioEngine.shared.activePlaylist != nil {
                        Menu {
                            ForEach(Array(tracks.enumerated()), id: \.offset) { idx, trackTitle in
                                Button {
                                    _ = FocusAudioEngine.shared.selectTrack(at: idx)
                                } label: {
                                    if trackTitle == title {
                                        Label(trackTitle, systemImage: "checkmark")
                                    } else {
                                        Text(trackTitle)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "music.note")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.indigo)
                                Text(title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Select calm break track")
                    } else {
                        Image(systemName: "music.note")
                            .font(.caption2)
                            .foregroundStyle(Theme.indigo)
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if FocusAudioEngine.shared.activePlaylist != nil {
                        Button {
                            _ = FocusAudioEngine.shared.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.indigo)
                        }
                        .buttonStyle(.plain)
                        .help("Skip to next track")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.indigo.opacity(0.10)))
            }
        }
    }

    // MARK: - Breath Pacer

    private var breathingSection: some View {
        VStack(spacing: Theme.Space.l) {
            Picker("Technique", selection: $technique) {
                ForEach(BreathingTechnique.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let state = BreakGuide.breathingState(technique: technique, cycleElapsed: elapsed)

                VStack(spacing: Theme.Space.m) {
                    ZStack {
                        Circle()
                            .fill(Theme.coral.opacity(0.08))
                            .frame(width: 180, height: 180)

                        Circle()
                            .stroke(Theme.coral.opacity(0.3), lineWidth: 2)
                            .frame(width: 180, height: 180)

                        Circle()
                            .fill(Theme.coral.opacity(0.25))
                            .frame(width: 130, height: 130)
                            .scaleEffect(pacerScale(for: state))
                            .animation(.easeInOut(duration: 0.8), value: state.phase)

                        VStack(spacing: 2) {
                            Text(state.phase.rawValue)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.coral)
                            Text(String(format: "%.0fs", max(0, state.phaseDuration - state.phaseElapsed)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 200)

                    Text(state.instruction)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.m)
                }
            }
        }
        .padding(.vertical, Theme.Space.s)
    }

    private func pacerScale(for state: BreathingState) -> CGFloat {
        switch state.phase {
        case .inhale:
            return 0.8 + CGFloat(state.progress) * 0.4
        case .holdIn:
            return 1.2
        case .exhale:
            return 1.2 - CGFloat(state.progress) * 0.4
        case .holdOut:
            return 0.8
        }
    }

    // MARK: - 20-20-20 Eye Relief

    private var eyeReliefSection: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "eye")
                .font(.system(size: 36))
                .foregroundStyle(Theme.cyan)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.cyan.opacity(0.12)))

            Text("20-20-20 Rule")
                .font(.headline)

            Text("Look at an object at least 20 feet (6 meters) away for 20 seconds. This relaxes your ciliary eye muscles and resets binocular convergence.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    .frame(width: 110, height: 110)

                Circle()
                    .trim(from: 0, to: CGFloat(eyeTimerSeconds) / 20.0)
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))

                Text("\(eyeTimerSeconds)s")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.vertical, Theme.Space.s)

            Button {
                startEyeReset()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isEyeTimerRunning ? "arrow.clockwise" : "play.fill")
                    Text(isEyeTimerRunning ? "Restart 20s" : "Start 20s Reset")
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, Theme.Space.s)
    }

    private func startEyeReset() {
        eyeTimerSeconds = 20
        isEyeTimerRunning = true
        Task { @MainActor in
            while eyeTimerSeconds > 0 && isEyeTimerRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if eyeTimerSeconds > 0 {
                    eyeTimerSeconds -= 1
                }
            }
            if eyeTimerSeconds == 0 {
                isEyeTimerRunning = false
                VoiceOutput.shared.speak("Eye reset complete.")
            }
        }
    }

    // MARK: - Desk Stretches

    private var stretchesSection: some View {
        VStack(spacing: Theme.Space.m) {
            ForEach(BreakGuide.stretches) { stretch in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    Image(systemName: stretch.iconName)
                        .font(.system(size: 18))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(Theme.coral)
                        .background(Circle().fill(Theme.coral.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stretch.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(stretch.durationSeconds)s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text(stretch.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
        }
        .frame(maxWidth: 480)
    }

    private var endBreakButton: some View {
        let totalMinutes = Int(((engine.breakTotal ?? 300) / 60.0).rounded())
        let atMaxBreak = totalMinutes >= 15
        return VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.m) {
                Button {
                    engine.extendBreak(minutes: 2)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                        Text(atMaxBreak ? "Max 15m" : "+2m Rest")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                }
                .buttonStyle(.bordered)
                .tint(Theme.coral)
                .disabled(atMaxBreak)
                .help(atMaxBreak ? "Maximum break duration reached (15m)" : "Extend break by 2 minutes (max 15m)")

                Button {
                    engine.endBreak()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("End Break & Lock Back In")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.coral)
            }
            Text("\(totalMinutes) / 15m break budget used")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
