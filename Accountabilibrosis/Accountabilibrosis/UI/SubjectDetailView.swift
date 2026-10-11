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
                        PresetThumbnail(preset: subject.preset).frame(width: 140)
                        Text(subject.preset.title).font(.callout).foregroundStyle(.secondary)
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
        block(subject.sites.count == 1 ? "Site" : "Sites") {
            ForEach(subject.sites, id: \.self) { site in
                Text(site).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        }
    }

    private var appsBlock: some View {
        block("Allowed apps") {
            HStack(spacing: Theme.Space.s) {
                ForEach(subject.allowedApps) { app in
                    AppIcon(bundleID: app.bundleID)
                        .frame(width: 28, height: 28)
                        .help(app.name)
                }
                Text(subject.allowedApps.isEmpty ? "Chrome and Finder only" : "+ Chrome and Finder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
