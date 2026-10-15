import SwiftUI

/// One subject: its setup at a glance, the LOCK IN button and its stats.
struct SubjectDetailView: View {
    let model: AppModel
    let subject: Subject
    @State private var isEditing = false
    @State private var isChoosingMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        if subject.usesCustomLayout {
                            CustomLayoutThumbnail(slots: subject.slots).frame(width: 140)
                            Text("Custom").font(.callout).foregroundStyle(.secondary)
                        } else {
                            PresetThumbnail(preset: subject.preset).frame(width: 140)
                            Text(subject.preset.title).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        sitesBlock
                        appsBlock
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    isChoosingMode = true
                } label: {
                    Text("LOCK IN")
                        .tracking(3)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                SubjectStatsSection(model: model, subjectID: subject.id)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(subject.name)
        .sheet(isPresented: $isEditing) {
            SubjectEditorView(model: model, subject: subject)
        }
        .sheet(isPresented: $isChoosingMode) {
            LockInSheet(model: model, subject: subject)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(subject.name)
                .font(Theme.titleFont)
                .lineLimit(1)
            Spacer()
            Button("Edit") { isEditing = true }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var sitesBlock: some View {
        block(subject.slots.count == 1 ? "Window" : "Windows") {
            ForEach(subject.slots) { slot in
                HStack(spacing: Theme.Space.s) {
                    switch slot.kind {
                    case .website:
                        Image(systemName: "globe").frame(width: 20)
                        Text(slot.urls.first ?? "").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        if slot.urls.count > 1 {
                            Text("+\(slot.urls.count - 1) tab\(slot.urls.count == 2 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    case .app:
                        AppIcon(bundleID: slot.app?.bundleID ?? "").frame(width: 20, height: 20)
                        Text(slot.app?.name ?? "App")
                        if let folder = slot.folder {
                            Text(folder).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            Text("Websites open in \(subject.browser.title). Other apps: \(subject.unusedApps == .quit ? "quit" : "hidden").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Read-only: allowed sites and apps are changed in one place, the Edit sheet.
    private var appsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            block("Allowed sites") {
                if subject.extraDomains.isEmpty {
                    Text("None yet. Sites you allow during a session are saved here. Edit the subject to change them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(subject.extraDomains, id: \.self) { host in
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "globe").frame(width: 20)
                        Text(host).lineLimit(1)
                    }
                }
            }
            block("Allowed apps") {
                if subject.allowedApps.isEmpty {
                    Text("None yet. Apps you unblock during a session are saved here. Edit the subject to change them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(subject.allowedApps) { app in
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 20, height: 20)
                        Text(app.name)
                    }
                }
            }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            content()
        }
    }
}
