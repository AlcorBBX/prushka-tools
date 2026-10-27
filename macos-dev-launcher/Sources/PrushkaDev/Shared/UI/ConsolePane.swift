import AppKit
import SwiftUI

/// AppKit console for live process output. SwiftUI `Text` + `textSelection` freezes on large/live logs.
struct ConsolePane: NSViewRepresentable {
    var source: any ConsoleTextSource
    /// Observed trigger only — the string itself is read inside `updateNSView`.
    var revision: Int
    var isLive: Bool = false
    var emptyPlaceholder: String = "Run to see output."

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.secondaryLabelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.string = emptyPlaceholder

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.appliedRevision = -1
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let coordinator = context.coordinator
        guard coordinator.appliedRevision != revision else { return }
        coordinator.appliedRevision = revision

        let raw = source.consoleText
        let text = raw.isEmpty ? emptyPlaceholder : raw
        let isPlaceholder = raw.isEmpty
        textView.textColor = isPlaceholder ? NSColor.secondaryLabelColor : NSColor.labelColor

        if isPlaceholder {
            textView.string = emptyPlaceholder
            coordinator.appliedLength = emptyPlaceholder.utf16.count
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]

        let current = textView.string
        if current != emptyPlaceholder, text.hasPrefix(current) {
            let suffix = String(text.dropFirst(current.count))
            if !suffix.isEmpty {
                textView.textStorage?.beginEditing()
                textView.textStorage?.append(NSAttributedString(string: suffix, attributes: attrs))
                textView.textStorage?.endEditing()
            }
        } else if current != text {
            textView.string = text
        }

        coordinator.appliedLength = text.utf16.count
        if isLive || coordinator.isNearBottom(in: scroll) {
            textView.scrollToEndOfDocument(nil)
        }
    }

    @MainActor
    final class Coordinator {
        var textView: NSTextView?
        var appliedRevision = -1
        var appliedLength = 0

        func isNearBottom(in scroll: NSScrollView) -> Bool {
            let visible = scroll.contentView.bounds
            let docHeight = scroll.documentView?.bounds.height ?? 0
            return visible.maxY >= docHeight - 48
        }
    }
}
