import Foundation

enum RepoRoot {
    static let defaultsKey = "repoRoot"

    static func isRepo(_ path: String) -> Bool {
        if case .success = Safety.validateRepo(path) {
            return true
        }
        return false
    }

    static func resolve(
        defaults: UserDefaults = .standard,
        hints: [URL] = defaultHints(),
        ignoringSaved: Bool = false
    ) -> String {
        if !ignoringSaved, let saved = defaults.string(forKey: defaultsKey), isRepo(saved) {
            return URL(fileURLWithPath: saved).standardizedFileURL.path
        }
        for hint in hints {
            if let found = walk(from: hint) {
                return found.path
            }
        }
        return FileManager.default.currentDirectoryPath
    }

    static func walk(from start: URL) -> URL? {
        var current = start.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            current.deleteLastPathComponent()
        }

        for _ in 0..<12 {
            if case .success(let url) = Safety.validateRepo(current.path) {
                return url
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
        return nil
    }

    static func defaultHints() -> [URL] {
        [
            URL(fileURLWithPath: #filePath),
            Bundle.main.bundleURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
    }
}
