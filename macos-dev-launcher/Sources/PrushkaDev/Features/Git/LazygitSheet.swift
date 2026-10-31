import SwiftUI

struct LazygitSheet: View {
    let executable: String
    let workingDirectory: URL
    let repoLabel: String
    let extraPath: String
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            LazygitTerminalView(
                executable: executable,
                workingDirectory: workingDirectory.path,
                extraPath: extraPath,
                onTerminated: onClose
            )
            .frame(minWidth: 720, minHeight: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LauncherTheme.canvas(scheme))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("lazygit — \(repoLabel)")
                    .font(.system(size: 15, weight: .semibold))
                Text(workingDirectory.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Close") { onClose() }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LauncherTheme.sidebar(scheme))
    }
}
