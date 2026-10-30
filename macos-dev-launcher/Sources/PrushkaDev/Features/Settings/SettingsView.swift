import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var pathDraft = ""

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

            rebuildSection
        }
        .onAppear { pathDraft = model.repoRoot }
        .onChange(of: model.repoRoot) { _, newValue in
            pathDraft = newValue
        }
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
