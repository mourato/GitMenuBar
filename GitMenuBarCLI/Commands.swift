import ArgumentParser
import Foundation

struct RepositoryCommandOptions: ParsableArguments {
    @Option(name: .long, help: "Repository path scope (default: current working directory).")
    var path: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Use staged changes only.")
    var staged: Bool = false

    @Flag(name: .long, help: "Use all working tree changes.")
    var all: Bool = false

    @Flag(name: .long, help: "Emit plain text instead of JSON.")
    var plain: Bool = false

    @Flag(name: .long, help: "Emit JSON output (default; accepted for agent scripts).")
    var json: Bool = false

    @Option(name: .long, help: "Commit message override (still runs Message policy).")
    var message: String?

    func validate() throws {
        if staged, all {
            throw ValidationError("Use only one of --staged or --all.")
        }
    }

    var scopeOptions: CompanionCLIScopeOptions {
        CompanionCLIScopeOptions(
            repositoryPathScope: path,
            staged: staged,
            all: all,
            outputFormat: plain ? .plain : .json,
            messageOverride: message
        )
    }

    var prefersJSON: Bool {
        !plain
    }
}

struct MessageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "message",
        abstract: "Propose a commit message (JSON by default)."
    )

    @OptionGroup var options: RepositoryCommandOptions

    mutating func run() async throws {
        try options.validate()
        let service = CompanionCLIRuntime.serviceInstance()

        do {
            let message = try await service.proposeMessage(options: options.scopeOptions)

            if options.prefersJSON {
                let payload = CompanionCLIMessageResult(message: message)
                let json = try CompanionCLIEncoder.encodeJSON(payload)
                CompanionCLIRuntime.printJSON(json)
            } else {
                CompanionCLIRuntime.printPlain(message)
            }
        } catch let error as CompanionCLIService.Error {
            try CompanionCLIRuntime.finishWithError(error, jsonPreferred: options.prefersJSON)
        }
    }
}

struct CommitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commit",
        abstract: "Propose or apply a single commit plan."
    )

    @OptionGroup var options: RepositoryCommandOptions

    @Flag(name: .long, help: "Stage and create a new commit (no amend/reset/push).")
    var apply: Bool = false

    mutating func validate() throws {
        try options.validate()
    }

    mutating func run() async throws {
        let service = CompanionCLIRuntime.serviceInstance()

        do {
            let plan = try await service.proposeCommit(options: options.scopeOptions)

            if apply {
                try await service.applyCommit(plan: plan, options: options.scopeOptions)
            }

            if options.prefersJSON {
                let json = try CompanionCLIEncoder.encodeJSON(plan)
                CompanionCLIRuntime.printJSON(json)
            } else {
                CompanionCLIRuntime.printPlain(plan.message)
            }
        } catch let error as CompanionCLIService.Error {
            try CompanionCLIRuntime.finishWithError(error, jsonPreferred: options.prefersJSON)
        }
    }
}

struct AtomicCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "atomic",
        abstract: "Propose or apply atomic commit groups."
    )

    @OptionGroup var options: RepositoryCommandOptions

    @Flag(name: .long, help: "Commit groups in order; stop on first failure without rollback.")
    var apply: Bool = false

    mutating func validate() throws {
        try options.validate()
        if options.message != nil {
            throw ValidationError("--message is not supported for atomic.")
        }
    }

    mutating func run() async throws {
        let service = CompanionCLIRuntime.serviceInstance()

        do {
            let plan = try await service.proposeAtomicPlan(options: options.scopeOptions)

            if apply {
                if let progress = try await service.applyAtomicPlan(plan: plan, options: options.scopeOptions) {
                    if options.prefersJSON {
                        let json = try CompanionCLIEncoder.encodeJSON(progress)
                        CompanionCLIRuntime.printJSON(json)
                    } else {
                        CompanionCLIRuntime.printPlain(progress.error)
                        for (index, group) in progress.completedGroups.enumerated() {
                            CompanionCLIRuntime.printPlain("Completed group \(index + 1): \(group.message)")
                        }
                        for (index, group) in progress.remainingGroups.enumerated() {
                            CompanionCLIRuntime.printPlain("Remaining group \(index + 1): \(group.message)")
                        }
                    }
                    throw ExitCode(CompanionCLIExitCode.operationalFailure.rawValue)
                }
            }

            if options.prefersJSON {
                let json = try CompanionCLIEncoder.encodeJSON(plan)
                CompanionCLIRuntime.printJSON(json)
            } else {
                for (index, group) in plan.groups.enumerated() {
                    CompanionCLIRuntime.printPlain("Group \(index + 1): \(group.message)")
                    for file in group.files {
                        CompanionCLIRuntime.printPlain("  - \(file)")
                    }
                }
            }
        } catch let error as CompanionCLIService.Error {
            try CompanionCLIRuntime.finishWithError(error, jsonPreferred: options.prefersJSON)
        }
    }
}
