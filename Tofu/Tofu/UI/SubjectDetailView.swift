import SwiftUI

/// One subject: its setup at a glance, the LOCK IN button and its stats.
struct SubjectDetailView: View {
    let model: AppModel
    let subject: Subject
    @State private var isEditing = false
    @State private var isChoosingMode = false
    @State private var siteDraft = ""
    @State private var isPickingApps = false
    @State private var appDraft: [AllowedApp] = []

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
        .sheet(isPresented: $isPickingApps, onDismiss: saveApps) {
            AppPickerView(selection: $appDraft)
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

    private var appsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            block("Allowed sites") {
                if subject.extraDomains.isEmpty {
                    Text("None yet. Sites you allow during a session are saved here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(subject.extraDomains, id: \.self) { host in
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "globe").frame(width: 20)
                        Text(host).lineLimit(1)
                        Spacer()
                        Button { removeSite(host) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Stop allowing \(host)")
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    TextField("Add a site, e.g. piazza.com", text: $siteDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") { addSite() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(siteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            block("Allowed apps") {
                if subject.allowedApps.isEmpty {
                    Text("None yet. Apps you unblock during a session are saved here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(subject.allowedApps) { app in
                    HStack(spacing: Theme.Space.s) {
                        AppIcon(bundleID: app.bundleID).frame(width: 20, height: 20)
                        Text(app.name)
                        Spacer()
                        Button { removeApp(app) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .help("Stop allowing \(app.name)")
                    }
                }
                Button("Edit apps…") {
                    appDraft = subject.allowedApps
                    isPickingApps = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func addSite() {
        let raw = siteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = DomainMatcher.host(of: raw), !host.isEmpty else { return }
        let study = Set(subject.sites.compactMap { DomainMatcher.host(of: $0) })
        guard !study.contains(host), !subject.extraDomains.contains(where: { DomainMatcher.normalize($0) == host }) else {
            siteDraft = ""
            return
        }
        var updated = subject
        updated.extraDomains.append(host)
        model.updateSubject(updated)
        siteDraft = ""
    }

    private func removeSite(_ host: String) {
        var updated = subject
        updated.extraDomains.removeAll { $0 == host }
        model.updateSubject(updated)
    }

    private func removeApp(_ app: AllowedApp) {
        var updated = subject
        updated.allowedApps.removeAll { $0.bundleID == app.bundleID }
        model.updateSubject(updated)
    }

    private func saveApps() {
        var updated = subject
        guard updated.allowedApps != appDraft else { return }
        updated.allowedApps = appDraft
        model.updateSubject(updated)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(Theme.captionFont).foregroundStyle(.secondary)
            content()
        }
    }
}
