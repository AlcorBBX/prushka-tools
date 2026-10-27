import SwiftUI

struct ToolsView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text: [String: String] = [:]
    @State private var flags: [String: Bool] = [:]
    @State private var slideForward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let actionError = model.actionError {
                ErrorBanner(message: actionError)
            }
            if model.tools.isEmpty {
                emptyTools
            } else {
                picker
                form
                output
            }
        }
        .onAppear { seed(model.selectedTool) }
        .onChange(of: model.selectedToolID) { _, _ in
            seed(model.selectedTool)
        }
        .onChange(of: model.tools.map(\.id)) { _, _ in
            seed(model.selectedTool)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
            value: model.selectedToolID
        )
    }

    private var picker: some View {
        SlidingToolTabs(tools: model.tools, selection: Bindable(model).selectedToolID) { forward in
            slideForward = forward
        }
    }

    @ViewBuilder
    private var form: some View {
        if let tool = model.selectedTool {
            let copy = ToolCopy.lookup(tool.id)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(copy.kicker)
                GroupedCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(copy.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(tool.args) { arg in
                            field(arg, toolID: tool.id)
                        }
                        HStack(spacing: 10) {
                            if model.toolIsRunning(tool.id) {
                                Button("Stop") { model.cancelTool() }
                                    .buttonStyle(PressStyle())
                                    .foregroundStyle(.red)
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button {
                                    Task {
                                        await model.run(tool: tool, text: text, flags: flags)
                                    }
                                } label: {
                                    Text("Run")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 7)
                                        .background(Capsule(style: .continuous).fill(LauncherTheme.tint(.tools)))
                                }
                                .buttonStyle(PressStyle())
                                .disabled(!canRun(tool))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14)
                }
                Text(copy.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .id(tool.id)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: slideForward ? 18 : -18)),
                        removal: .opacity.combined(with: .offset(x: slideForward ? -12 : 12))
                    )
            )
        }
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(model.toolOutputTitle.isEmpty ? "Output" : model.toolOutputTitle)
            GroupedCard {
                ScrollView {
                    Text(model.toolOutput.isEmpty ? "Run a tool to see its output here." : model.toolOutput)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(model.toolOutput.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .frame(minHeight: 180, maxHeight: 320)
            }
        }
    }

    private var emptyTools: some View {
        GroupedCard {
            Text("No tools in scripts/registry.json.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(14)
        }
    }

    @ViewBuilder
    private func field(_ arg: ToolArg, toolID: String) -> some View {
        let copy = ToolCopy.field(toolID: toolID, arg: arg.name)
        if arg.type == "boolean" {
            Toggle(isOn: flagBinding(arg)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.title)
                        .font(.system(size: 15, weight: .medium))
                    if !copy.hint.isEmpty {
                        Text(copy.hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(copy.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(copy.placeholder, text: textBinding(arg))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LauncherTheme.field(scheme))
                    }
                if !copy.hint.isEmpty {
                    Text(copy.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func textBinding(_ arg: ToolArg) -> Binding<String> {
        Binding(
            get: { text[arg.name] ?? "" },
            set: { text[arg.name] = $0 }
        )
    }

    private func flagBinding(_ arg: ToolArg) -> Binding<Bool> {
        Binding(
            get: { flags[arg.name] ?? false },
            set: { flags[arg.name] = $0 }
        )
    }

    private func canRun(_ tool: RegistryTool) -> Bool {
        guard model.rootIsValid, !model.toolIsRunning(tool.id) else { return false }
        return tool.args.allSatisfy { arg in
            guard arg.required, arg.type != "boolean" else { return true }
            let value = text[arg.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty
        }
    }

    private func seed(_ tool: RegistryTool?) {
        guard let tool else { return }
        for arg in tool.args {
            if text[arg.name] == nil {
                text[arg.name] = arg.defaultString ?? ""
            }
            if flags[arg.name] == nil {
                flags[arg.name] = arg.defaultBool ?? false
            }
        }
    }
}

private struct SlidingToolTabs: View {
    let tools: [RegistryTool]
    @Binding var selection: String
    var onMove: (Bool) -> Void
    @Namespace private var chip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tools) { tool in
                let active = selection == tool.id
                Button {
                    let oldIndex = tools.firstIndex { $0.id == selection } ?? 0
                    let newIndex = tools.firstIndex { $0.id == tool.id } ?? 0
                    onMove(newIndex >= oldIndex)
                    withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) {
                        selection = tool.id
                    }
                } label: {
                    Text(tool.shortTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "tool-chip", in: chip)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.label)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
        }
    }
}

private enum ToolCopy {
    struct TextCopy {
        var title: String
        var hint: String
        var placeholder: String
    }

    struct ScreenCopy {
        var kicker: String
        var summary: String
        var footnote: String
    }

    static func lookup(_ id: String) -> ScreenCopy {
        switch id {
        case "tab-source-fetch":
            ScreenCopy(
                kicker: "Download",
                summary: "Saves one song from the tab catalog into a local cache. The demo project stays unchanged until you fill it.",
                footnote: "Song id is the catalog number, for example 9489. Force download replaces a copy that is already cached."
            )
        case "tab-source-fill":
            ScreenCopy(
                kicker: "Fill demo",
                summary: "Builds a demo project from that cache: lyrics and arrangement land in the demo file for the slug you type.",
                footnote: "Demo is the slug in front/apps/web/scripts/demos, for example rooster. Download first if you have not fetched this song yet."
            )
        case "demo-notes-from-lead":
            ScreenCopy(
                kicker: "Vocals",
                summary: "Rebuilds karaoke notes from the Lead Vocals MIDI so each word sits on the pitch that is actually sung.",
                footnote: "Use the same demo slug you just filled. After this, leave that demo’s lyric timing on keep so the next fill does not wipe it."
            )
        default:
            ScreenCopy(
                kicker: "Tool",
                summary: "Runs a repository script.",
                footnote: "Uses the checkout path from Settings."
            )
        }
    }

    static func field(toolID: String, arg: String) -> TextCopy {
        switch (toolID, arg) {
        case (_, "song"):
            TextCopy(title: "Song id", hint: "Numeric id from the tab catalog.", placeholder: "9489")
        case ("tab-source-fetch", "force"):
            TextCopy(title: "Force download", hint: "Fetch again even when the cache already has this song.", placeholder: "")
        case (_, "demo"):
            TextCopy(title: "Demo", hint: "Slug of the demo config, not the song title.", placeholder: "rooster")
        case ("tab-source-fill", "fetch"):
            TextCopy(title: "Download first", hint: "Fetch the tab, then fill the demo in the same run.", placeholder: "")
        default:
            TextCopy(title: arg, hint: "", placeholder: arg)
        }
    }
}
