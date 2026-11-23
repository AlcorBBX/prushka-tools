import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var pathDraft = ""
    @State private var agentPathDraft = ""
    @State private var agentModelDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let actionError = model.actionError {
                ErrorBanner(message: actionError)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Checkout")
                GroupedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Repository path", text: $pathDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(8)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LauncherTheme.field(scheme))
                            }
                            .onSubmit { model.setRepoRoot(pathDraft) }

                        HStack(spacing: 10) {
                            Button("Save") { model.setRepoRoot(pathDraft) }
                                .buttonStyle(PressStyle())
                            Button("Choose…") { chooseFolder() }
                                .buttonStyle(PressStyle())
                            Button("Use detected") { model.useDetectedRoot() }
                                .buttonStyle(PressStyle())
                            Spacer(minLength: 0)
                            Text(model.rootIsValid ? "Registry found" : "Registry missing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(model.rootIsValid ? Color.green : Color.orange)
                        }
                    }
                    .padding(14)
                }
                Text(detectedCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Launcher")
                GroupedCard {
                    row("Poll", value: "Every 2 seconds")
                    CardDivider()
                    row("Discovery", value: "Port and process, not only this app")
                    CardDivider()
                    row("Sandbox", value: "Off")
                }
                Text("Services, tools, and logs all read this checkout. Changing it does not move the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            commitAgentSection

            rebuildSection
        }
        .onAppear {
            pathDraft = model.repoRoot
            agentPathDraft = model.commitAgent.customPath
            agentModelDraft = model.commitAgent.model
        }
        .onChange(of: model.commitAgent) { _, newValue in
            agentPathDraft = newValue.customPath
            agentModelDraft = newValue.model
        }
        .onChange(of: model.repoRoot) { _, newValue in
            pathDraft = newValue
        }
    }

    private var commitAgentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Commit agent")
            GroupedCard {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(
                        "Agent",
                        selection: Binding(
                            get: { model.commitAgent.provider },
                            set: { model.setCommitAgentProvider($0) }
                        )
                    ) {
                        ForEach(CommitAgentProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    TextField(
                        "Binary path (optional, default: \(model.commitAgent.provider.binaryName) on PATH)",
                        text: $agentPathDraft
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LauncherTheme.field(scheme))
                    }
                    .onSubmit { saveAgentDrafts() }

                    TextField(
                        "Model (default: \(model.commitAgent.provider.defaultModel); \(model.commitAgent.provider.modelHint))",
                        text: $agentModelDraft
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LauncherTheme.field(scheme))
                    }
                    .onSubmit { saveAgentDrafts() }

                    HStack(spacing: 10) {
                        Button("Save") { saveAgentDrafts() }
                            .buttonStyle(PressStyle())
                        Button("Choose…") { chooseAgentBinary() }
                            .buttonStyle(PressStyle())
                        Spacer(minLength: 0)
                        agentStatusLabel
                    }
                }
                .padding(14)
            }
            Text("Drafts commit messages in Git from the staged diff with model \(model.commitAgent.effectiveModel). Runs read-only with no tools; you still review and commit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var agentStatusLabel: some View {
        switch model.commitAgentStatus {
        case .success(let path):
            Text(path)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.green)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
        case .failure(let error):
            Text("Not found")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
                .help(error.localizedDescription)
        }
    }

    private func saveAgentDrafts() {
        model.setCommitAgentModel(agentModelDraft)
        model.setCommitAgentPath(agentPathDraft)
    }

    private func chooseAgentBinary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select the \(model.commitAgent.provider.label) CLI binary"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        agentPathDraft = url.path
        model.setCommitAgentPath(url.path)
    }

    private var rebuildSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Update")
            GroupedCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rebuild this app from tools/macos-dev-launcher (debug), then open a new instance and quit this one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if model.isRebuilding {
                            Button("Cancel") { model.cancelRebuild() }
                                .buttonStyle(PressStyle())
                                .foregroundStyle(.red)
                            ProgressView()
                                .controlSize(.small)
                            Text("Building…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await model.rebuildAndRelaunch() }
                            } label: {
                                Text("Rebuild & Relaunch")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(Capsule(style: .continuous).fill(LauncherTheme.tint(.settings)))
                            }
                            .buttonStyle(PressStyle())
                            .disabled(!model.rootIsValid)
                        }
                        Spacer(minLength: 0)
                    }

                    if !model.rebuildLog.isEmpty {
                        ScrollView {
                            Text(model.rebuildLog)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LauncherTheme.field(scheme))
                        )
                    }
                }
                .padding(14)
            }
            Text("Needs swift on your login PATH. Same as ./Scripts/package-app.sh in the launcher tree.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var detectedCaption: String {
        if model.detectedRoot.isEmpty {
            return "Scripts live in scripts/ at the repository root."
        }
        return "Detected \(model.detectedRoot)"
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the Prushka repository root"
        if !model.repoRoot.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: model.repoRoot)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pathDraft = url.path
        model.setRepoRoot(url.path)
    }
}
