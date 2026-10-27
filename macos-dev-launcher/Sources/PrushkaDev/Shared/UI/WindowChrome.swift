import AppKit
import SwiftUI

/// Paints the system title bar the same solid canvas color as the app (no grey material strip).
struct WindowChromeBinder: NSViewRepresentable {
    var scheme: ColorScheme

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.scheme = scheme
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.scheme = scheme
        nsView.applyChrome()
    }

    final class TrackerView: NSView {
        var scheme: ColorScheme = .dark

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyChrome()
        }

        func applyChrome() {
            guard let window else { return }

            let canvas = LauncherTheme.canvasNSColor(scheme)
            window.backgroundColor = canvas
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.toolbar = nil

            paintTitlebarSurface(window, color: canvas)

            // Title bar hierarchy can settle a tick later after style-mask changes.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.paintTitlebarSurface(window, color: LauncherTheme.canvasNSColor(self.scheme))
            }
        }

        private func paintTitlebarSurface(_ window: NSWindow, color: NSColor) {
            guard let close = window.standardWindowButton(.closeButton) else { return }

            var node: NSView? = close.superview
            while let view = node {
                view.wantsLayer = true
                view.layer?.backgroundColor = color.cgColor
                hideVisualEffects(in: view)
                if view.superview === window.contentView?.superview
                    || view.className.contains("Titlebar")
                    || view.className.contains("NSTitlebar")
                {
                    break
                }
                node = view.superview
            }

            if let themeFrame = window.contentView?.superview {
                hideVisualEffects(in: themeFrame)
                themeFrame.wantsLayer = true
                themeFrame.layer?.backgroundColor = color.cgColor
            }
        }

        private func hideVisualEffects(in root: NSView) {
            if let effect = root as? NSVisualEffectView {
                effect.isHidden = true
                effect.alphaValue = 0
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
            }
            for child in root.subviews {
                hideVisualEffects(in: child)
            }
        }
    }
}
