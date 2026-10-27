import Foundation

/// Buffer that AppKit `ConsolePane` can read without SwiftUI diffing the full string.
@MainActor
protocol ConsoleTextSource: AnyObject {
    var consoleText: String { get }
}
