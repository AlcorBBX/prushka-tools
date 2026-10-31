import AppKit
import SwiftTerm
import SwiftUI

/// Hosts `lazygit` inside an in-app PTY via SwiftTerm.
struct LazygitTerminalView: NSViewRepresentable {
    let executable: String
    let workingDirectory: String
    let extraPath: String
    var onTerminated: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTerminated: onTerminated)
    }

    @MainActor
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        view.processDelegate = context.coordinator
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        context.coordinator.terminalView = view
        return view
    }

    @MainActor
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.onTerminated = onTerminated
        context.coordinator.ensureStarted(
            executable: executable,
            workingDirectory: workingDirectory,
            extraPath: extraPath
        )
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.terminate()
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
        var onTerminated: () -> Void
        weak var terminalView: LocalProcessTerminalView?
        private var didStart = false
        private var didReportExit = false

        init(onTerminated: @escaping () -> Void) {
            self.onTerminated = onTerminated
        }

        @MainActor
        func ensureStarted(executable: String, workingDirectory: String, extraPath: String) {
            guard !didStart, let terminalView else { return }
            // Wait until SwiftUI has given the view a real size.
            guard terminalView.bounds.width > 40, terminalView.bounds.height > 40 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.ensureStarted(
                        executable: executable,
                        workingDirectory: workingDirectory,
                        extraPath: extraPath
                    )
                }
                return
            }
            didStart = true

            var env = ProcessInfo.processInfo.environment
            let basePath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            if extraPath.isEmpty {
                env["PATH"] = basePath
            } else {
                env["PATH"] = extraPath + ":" + basePath
            }
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"
            if env["LANG"] == nil || env["LANG"]?.isEmpty == true {
                env["LANG"] = "en_US.UTF-8"
            }

            let envPairs = env.map { "\($0.key)=\($0.value)" }.sorted()
            terminalView.startProcess(
                executable: executable,
                args: [],
                environment: envPairs,
                execName: "lazygit",
                currentDirectory: workingDirectory
            )
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }

        @MainActor
        func terminate() {
            terminalView?.terminate()
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.didReportExit else { return }
                self.didReportExit = true
                self.onTerminated()
            }
        }
    }
}
