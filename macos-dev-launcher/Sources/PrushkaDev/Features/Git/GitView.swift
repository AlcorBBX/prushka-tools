import SwiftUI

struct GitView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let actionError = model.actionError {
                ErrorBanner(message: actionError)
            }
            if !model.rootIsValid {
                GroupedCard {
                    Text("Point Settings at the Prushka checkout. Git works on nested repos front/, tools/, and scripts/.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            } else {
                repoPicker
                statusCard
                unpushedCard
                messageCard
                lazygitCard
            }
        }
        .onAppear {
            Task { await model.refreshGitStatus() }
        }
        .onChange(of: model.repoRoot) { _, _ in
            Task { await model.refreshGitStatus() }
        }
    }

    private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Repository")
            GroupedCard {
                HStack(spacing: 8) {
                    ForEach(GitCatalog.repos) { repo in
                        let available = model.gitRepoIsAvailable(repo)
                        let selected = model.selectedGitRepoID == repo.id
                        Button {
                            model.selectGitRepo(repo.id)
                        } label: {
                            Text(repo.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selected ? .white : (available ? .primary : .secondary))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(
                                            selected
                                                ? LauncherTheme.tint(.git)
                                                : Color.primary.opacity(available ? 0.06 : 0.03)
                                        )
                                }
                        }
                        .buttonStyle(PressStyle())
                        .disabled(!available)
                        .opacity(available ? 1 : 0.45)
                        .help(available ? repo.relativePath : "No .git under \(repo.relativePath)/")
                    }
                    Spacer(minLength: 0)
                    if model.gitBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(14)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel("Status")
                Spacer(minLength: 0)
                if !model.gitBranch.isEmpty {
                    Text(model.gitBranch)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                if let upstream = model.gitUpstream {
                    Text(upstream)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.04)))
                }
                if model.gitAhead > 0 {
                    metaChip("↑\(model.gitAhead)", tint: LauncherTheme.tint(.git))
                }
                if model.gitBehind > 0 {
                    metaChip("↓\(model.gitBehind)", tint: Color(red: 0.94, green: 0.38, blue: 0.30))
                }
            }
            if let gitStatusError = model.gitStatusError {
                ErrorBanner(message: gitStatusError)
            }
            GroupedCard {
                VStack(alignment: .leading, spacing: 12) {
                    actionsRow
                    if model.gitEntries.isEmpty {
                        Text(model.gitStatusError == nil ? "Working tree clean." : " ")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        fileList
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private var unpushedCard: some View {
        if !model.gitUnpushedCommits.isEmpty || (!model.gitHasUpstream && model.gitStatusError == nil && !model.gitBranch.isEmpty) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(model.gitHasUpstream ? "Unpushed" : "Local only")
                GroupedCard {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.gitUnpushedCommits.isEmpty {
                            Text(
                                model.gitHasUpstream
                                    ? "Nothing to push — branch matches upstream."
                                    : "No upstream set. Local commits not on any remote will show here."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(14)
                        } else {
                            ForEach(Array(model.gitUnpushedCommits.enumerated()), id: \.element.id) { index, commit in
                                if index > 0 {
                                    CardDivider()
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(commit.hash)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(LauncherTheme.tint(.git))
                                        .frame(width: 56, alignment: .leading)
                                    Text(commit.subject)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
                if !model.gitHasUpstream {
                    Text("Set upstream (git push -u) in lazygit before Push works from here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            gitButton("Refresh") {
                Task { await model.refreshGitStatus() }
            }
            gitButton("Stage selected") {
                Task { await model.stageGit(all: false) }
            }
            .disabled(model.gitSelectedPaths.isEmpty || model.gitBusy)
            gitButton("Stage all") {
                Task { await model.stageGit(all: true) }
            }
            .disabled(model.gitBusy || model.gitEntries.isEmpty)
            gitButton("Unstage selected") {
                Task { await model.unstageGit(all: false) }
            }
            .disabled(model.gitSelectedPaths.isEmpty || model.gitBusy)
            gitButton("Unstage all") {
                Task { await model.unstageGit(all: true) }
            }
            .disabled(model.gitBusy || model.gitEntries.isEmpty)
            Spacer(minLength: 0)
            if !model.gitEntries.isEmpty {
                Button(model.gitSelectedPaths.count == model.gitEntries.count ? "Clear" : "Select all") {
                    if model.gitSelectedPaths.count == model.gitEntries.count {
                        model.clearGitPathSelection()
                    } else {
                        model.selectAllGitPaths()
                    }
                }
                .buttonStyle(PressStyle())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.gitEntries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    CardDivider()
                }
                Button {
                    model.toggleGitPath(entry.path)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.gitSelectedPaths.contains(entry.path) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                model.gitSelectedPaths.contains(entry.path)
                                    ? LauncherTheme.tint(.git)
                                    : Color.secondary
                            )
                        Text(entry.codeLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        Text(entry.path)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(entry.statusLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Commit message")
            GroupedCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Draft via Cursor agent from staged changes (Conventional Commits with scope). Commit uses the text below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: Bindable(model).commitMessageDraft)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 110, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LauncherTheme.field(scheme))
                        )

                    HStack(spacing: 10) {
                        Button {
                            Task { await model.generateCommitMessage() }
                        } label: {
                            Text(model.gitGenerating ? "Generating…" : "Generate")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Capsule(style: .continuous).fill(LauncherTheme.tint(.git)))
                        }
                        .buttonStyle(PressStyle())
                        .disabled(model.gitBusy || model.gitGenerating)

                        Button {
                            Task { await model.commitWithDraft() }
                        } label: {
                            Text("Commit")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(red: 0.20, green: 0.72, blue: 0.48))
                                )
                        }
                        .buttonStyle(PressStyle())
                        .disabled(
                            model.gitBusy
                                || model.gitGenerating
                                || model.commitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        if model.canPushGit {
                            Button {
                                Task { await model.pushGit() }
                            } label: {
                                Text(model.gitAhead > 1 ? "Push \(model.gitAhead)" : "Push")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color(red: 0.22, green: 0.48, blue: 0.98))
                                    )
                            }
                            .buttonStyle(PressStyle())
                            .disabled(model.gitBusy || model.gitGenerating)
                        }

                        if model.gitGenerating || model.gitBusy {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button("Copy") {
                            model.copyCommitMessage()
                        }
                        .buttonStyle(PressStyle())
                        .disabled(model.commitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer(minLength: 0)
                    }
                }
                .padding(14)
            }
            Text("Commit uses git commit -F on staged files; Push runs git push (no --force). Hooks still run.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var lazygitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("lazygit")
            GroupedCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open lazygit in Terminal.app for the selected repo.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Branches, rebase, force-push — outside this launcher.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.openLazygit()
                    } label: {
                        Text("Open lazygit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Capsule(style: .continuous).fill(LauncherTheme.tint(.git)))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.selectedGitRepo.map { !model.gitRepoIsAvailable($0) } ?? true)
                }
                .padding(14)
            }
        }
    }

    private func gitButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(PressStyle())
        .disabled(model.gitBusy)
    }

    private func metaChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
    }
}
