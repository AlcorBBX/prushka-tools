import Foundation

enum GitRunner {
    enum Action: Sendable {
        case status
        case stageAll
        case unstageAll
        case stage(paths: [String])
        case unstage(paths: [String])
        case cachedDiff
        case shortLog
    }

    static func run(
        action: Action,
        repo: NestedGitRepo,
        root: URL,
        extraPath: String?
    ) async -> Result<CommandOutput, Safety.Failure> {
        let cwd: URL
        switch Safety.gitRepoURL(repo: repo, root: root) {
        case .failure(let error):
            return .failure(error)
        case .success(let url):
            cwd = url
        }

        let arguments: [String]
        switch buildArguments(action) {
        case .failure(let error):
            return .failure(error)
        case .success(let args):
            arguments = args
        }

        let output = await ProcessRunner.run(
            arguments: arguments,
            cwd: cwd,
            extraPath: extraPath,
            timeout: .seconds(60)
        )
        return .success(output)
    }

    private static func buildArguments(_ action: Action) -> Result<[String], Safety.Failure> {
        switch action {
        case .status:
            return .success(["git", "status", "--porcelain=v1", "-b"])
        case .stageAll:
            return .success(["git", "add", "-A"])
        case .unstageAll:
            return .success(["git", "restore", "--staged", ":/"])
        case .stage(let paths):
            switch Safety.sanitizeGitPaths(paths) {
            case .failure(let error):
                return .failure(error)
            case .success(let safe):
                return .success(["git", "add", "--"] + safe)
            }
        case .unstage(let paths):
            switch Safety.sanitizeGitPaths(paths) {
            case .failure(let error):
                return .failure(error)
            case .success(let safe):
                return .success(["git", "restore", "--staged", "--"] + safe)
            }
        case .cachedDiff:
            return .success(["git", "diff", "--cached", "--no-color"])
        case .shortLog:
            return .success(["git", "log", "-5", "--oneline", "--no-color"])
        }
    }
}
