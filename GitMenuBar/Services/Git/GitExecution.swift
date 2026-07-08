//
//  GitExecution.swift
//  GitMenuBar
//

import Foundation

/// Shared git-execution primitives reused by `GitManager` and the services it
/// delegates to (e.g. `GitBranchService`). Centralizing them removes the
/// copy-pasted `runOnBackground` / `publishOnMainActor` / `executeGitCommand`
/// helpers that previously lived in each type.
enum GitExecution {
    static func runOnBackground<T>(_ operation: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: operation())
            }
        }
    }

    static func publishOnMainActor(_ update: @escaping @MainActor () -> Void) async {
        await MainActor.run(body: update)
    }

    static func executeGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false,
        additionalEnvironment: [String: String] = [:],
        using runner: GitCommandRunner
    ) -> (output: String, failure: Bool) {
        runner.runGitCommand(
            in: directory,
            args: args,
            useAuth: useAuth,
            additionalEnvironment: additionalEnvironment
        )
    }

    static func missingRepositoryError() -> NSError {
        NSError(
            domain: "GitManager",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No repository path configured"]
        )
    }
}
