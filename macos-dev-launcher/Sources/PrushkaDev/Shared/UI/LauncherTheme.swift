import AppKit
import SwiftUI

enum LauncherMotion {
    /// Fast start, soft landing — use for expand/collapse and mode switches.
    static func easeOut(reduceMotion: Bool, duration: Double = 0.36) -> Animation? {
        reduceMotion
            ? nil
            : .timingCurve(0.16, 0.84, 0.18, 1, duration: duration)
    }

    static func easeOutQuick(reduceMotion: Bool) -> Animation? {
        easeOut(reduceMotion: reduceMotion, duration: 0.28)
    }
}

enum LauncherTheme {
    static func canvas(_ scheme: ColorScheme) -> Color {
        Color(nsColor: canvasNSColor(scheme))
    }

    static func canvasNSColor(_ scheme: ColorScheme) -> NSColor {
        scheme == .dark
            ? NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.045) : Color.white
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.86)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    static func field(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    static func tint(_ section: AppSection) -> Color {
        switch section {
        case .services: Color(red: 0.22, green: 0.48, blue: 0.98)
        case .checks: Color(red: 0.20, green: 0.72, blue: 0.48)
        case .tools: Color(red: 0.58, green: 0.34, blue: 0.96)
        case .logs: Color(red: 0.16, green: 0.70, blue: 0.78)
        case .settings: Color(red: 0.94, green: 0.38, blue: 0.30)
        }
    }
}

enum ShellLayout: Equatable {
    case split
    case rail
    case stacked

    init(width: CGFloat) {
        if width >= 880 {
            self = .split
        } else if width >= 640 {
            self = .rail
        } else {
            self = .stacked
        }
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72),
                value: configuration.isPressed
            )
            .pointingHandCursor()
    }
}

extension View {
    /// Shows the pointing-hand cursor over clickable controls.
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
