import Foundation

public enum CompanionCLIOutputFormat: Sendable {
    case json
    case plain
}

public struct CompanionCLIScopeOptions: Sendable {
    public let repositoryPathScope: String
    public let staged: Bool
    public let all: Bool
    public let outputFormat: CompanionCLIOutputFormat
    public let messageOverride: String?

    public init(
        repositoryPathScope: String,
        staged: Bool,
        all: Bool,
        outputFormat: CompanionCLIOutputFormat,
        messageOverride: String?
    ) {
        self.repositoryPathScope = repositoryPathScope
        self.staged = staged
        self.all = all
        self.outputFormat = outputFormat
        self.messageOverride = messageOverride
    }

    public func resolvedDiffScope() -> String? {
        if staged {
            return DiffScope.staged.rawValue
        }
        if all {
            return DiffScope.all.rawValue
        }
        return nil
    }

    func resolvedDiffScopeValue() -> DiffScope? {
        if staged {
            return .staged
        }
        if all {
            return .all
        }
        return nil
    }
}

public struct CompanionCLIMessageResult: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let message: String

    public init(message: String) {
        schemaVersion = Self.schemaVersion
        self.message = message
    }
}

public struct CompanionCLICommitPlan: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let scope: String
    public let files: [String]
    public let message: String

    init(scope: DiffScope, files: [String], message: String) {
        schemaVersion = Self.schemaVersion
        self.scope = scope.rawValue
        self.files = files
        self.message = message
    }
}

public struct CompanionCLIAtomicGroupDTO: Codable, Sendable, Equatable {
    public let files: [String]
    public let message: String

    init(group: AtomicCommitGroup) {
        files = group.files
        message = group.message
    }

    public init(files: [String], message: String) {
        self.files = files
        self.message = message
    }
}

public struct CompanionCLIAtomicPlan: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let groups: [CompanionCLIAtomicGroupDTO]

    init(groups: [AtomicCommitGroup]) {
        schemaVersion = Self.schemaVersion
        self.groups = groups.map(CompanionCLIAtomicGroupDTO.init(group:))
    }
}

public struct CompanionCLIAtomicApplyProgress: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let error: String
    public let completedGroups: [CompanionCLIAtomicGroupDTO]
    public let remainingGroups: [CompanionCLIAtomicGroupDTO]

    init(
        error: String,
        completedGroups: [AtomicCommitGroup],
        remainingGroups: [AtomicCommitGroup]
    ) {
        schemaVersion = Self.schemaVersion
        self.error = error
        self.completedGroups = completedGroups.map(CompanionCLIAtomicGroupDTO.init(group:))
        self.remainingGroups = remainingGroups.map(CompanionCLIAtomicGroupDTO.init(group:))
    }
}

public struct CompanionCLIErrorPayload: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let error: String
    public let exitCode: Int

    public init(error: String, exitCode: Int32) {
        schemaVersion = Self.schemaVersion
        self.error = error
        self.exitCode = Int(exitCode)
    }

    public init(error: String, exitCode: CompanionCLIExitCode) {
        self.init(error: error, exitCode: exitCode.rawValue)
    }
}

public extension CompanionCLIService {
    func proposeMessage(options: CompanionCLIScopeOptions) async throws -> String {
        let session = try await makeSession(options: options)
        return try await resolveMessage(session: session, options: options)
    }

    func proposeCommit(options: CompanionCLIScopeOptions) async throws -> CompanionCLICommitPlan {
        let session = try await makeSession(options: options)
        return try await buildCommitPlan(session: session, options: options)
    }

    func applyCommit(plan: CompanionCLICommitPlan, options: CompanionCLIScopeOptions) async throws {
        let session = try await makeSession(options: options)
        try await applyCommitPlan(session: session, plan: plan)
    }

    func proposeAtomicPlan(options: CompanionCLIScopeOptions) async throws -> CompanionCLIAtomicPlan {
        let session = try await makeSession(options: options)
        return try await buildAtomicPlan(session: session, options: options)
    }

    func applyAtomicPlan(
        plan: CompanionCLIAtomicPlan,
        options: CompanionCLIScopeOptions
    ) async throws -> CompanionCLIAtomicApplyProgress? {
        let session = try await makeSession(options: options)
        return try await applyAtomicPlan(session: session, plan: plan)
    }
}

public enum CompanionCLIEncoder {
    public static func encodeJSON(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CompanionCLIService.Error.operational("Failed to encode JSON output.")
        }
        return string
    }
}
