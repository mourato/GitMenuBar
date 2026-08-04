//
//  GitBranchService+Queries.swift
//  GitMenuBar
//

import Foundation

extension GitBranchService {
    func fetchLocalBranchesAsync() async -> [String] {
        await fetchLocalBranchesAsync(session: nil)
    }

    private func fetchLocalBranchesAsync(session: GitRefreshSession?) async -> [String] {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else { return [] }

        return await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["branch", "--format=%(refname:short)"])
            guard !result.failure else { return [String]() }
            return result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { $0 != "HEAD" }
        }
    }

    func fetchRemoteBranchesAsync() async -> [String] {
        await fetchRemoteBranchesAsync(session: nil)
    }

    private func fetchRemoteBranchesAsync(session: GitRefreshSession?) async -> [String] {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else { return [] }

        return await runOnBackground {
            let result = self.executeGitCommand(in: repositoryPath, args: ["branch", "-r", "--format=%(refname:short)"])
            guard !result.failure else { return [String]() }
            return result.output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { $0 != "HEAD" && $0 != "origin/HEAD" }
                .compactMap { branch in
                    branch.hasPrefix("origin/") ? String(branch.dropFirst(7)) : nil
                }
        }
    }

    func getDefaultBranchNameAsync() async -> String {
        await getDefaultBranchNameAsync(session: nil)
    }

    func getDefaultBranchNameAsync(session: GitRefreshSession?) async -> String {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else { return "main" }

        let detected: String? = await runOnBackground { () -> String? in
            let result = self.executeGitCommand(
                in: repositoryPath,
                args: ["symbolic-ref", "refs/remotes/origin/HEAD"]
            )
            if !result.failure, let last = result.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "/").last {
                return last
            }
            return nil
        }

        if let detected, !detected.isEmpty {
            await GitExecution.publishOnMainActor(ifCurrent: session) { self.defaultBranchName = detected }
            return detected
        }

        let fallback = await defaultBranchNameFallback(repositoryPath: repositoryPath)
        await GitExecution.publishOnMainActor(ifCurrent: session) { self.defaultBranchName = fallback }
        return fallback
    }

    private func defaultBranchNameFallback(repositoryPath: String) async -> String {
        let local = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["branch", "--format=%(refname:short)"]).output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if local.contains("main") {
            return "main"
        }
        if local.contains("master") {
            return "master"
        }
        return "main"
    }

    func resolveBranchInfoAsync() async -> [BranchInfo] {
        await resolveBranchInfoAsync(session: nil)
    }

    func resolveBranchInfoAsync(session: GitRefreshSession?) async -> [BranchInfo] {
        let repositoryPath = session?.repositoryPath ?? storedRepoPath
        guard !repositoryPath.isEmpty else { return [] }

        let localBranches = await fetchLocalBranchesAsync(session: session)
        let remoteBranches = await fetchRemoteBranchesAsync(session: session)
        let currentBranch = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let infos = await runOnBackground {
            var result: [BranchInfo] = []

            for localName in localBranches {
                let trackingStatus = self.resolveTrackingStatus(
                    localName: localName,
                    currentBranch: currentBranch,
                    remoteBranches: remoteBranches,
                    repositoryPath: repositoryPath
                )
                let lastCommitDate = self.lastCommitDate(for: localName, repositoryPath: repositoryPath)
                result.append(
                    BranchInfo(
                        name: localName,
                        isLocal: true,
                        isRemote: false,
                        isCurrent: localName == currentBranch,
                        trackingStatus: trackingStatus,
                        lastCommitDate: lastCommitDate
                    )
                )
            }

            let localSet = Set(localBranches)
            for remoteName in remoteBranches where !localSet.contains(remoteName) {
                let lastCommitDate = self.lastCommitDate(for: "origin/\(remoteName)", repositoryPath: repositoryPath)
                result.append(
                    BranchInfo(
                        name: remoteName,
                        isLocal: false,
                        isRemote: true,
                        isCurrent: false,
                        trackingStatus: .noRemote,
                        lastCommitDate: lastCommitDate
                    )
                )
            }

            return result
        }

        await GitExecution.publishOnMainActor(ifCurrent: session) {
            self.branchInfos = infos
        }

        return infos
    }

    /// Note: tracking-status resolution issues one synchronous git round-trip per
    /// local branch. Acceptable for typical repos; batch via a single `for-each-ref`
    /// if branch counts grow large.
    private func resolveTrackingStatus(
        localName: String,
        currentBranch _: String,
        remoteBranches: [String],
        repositoryPath: String
    ) -> BranchTrackingStatus {
        let upstreamCheck = executeGitCommand(in: repositoryPath, args: ["rev-parse", "--verify", "--quiet", "\(localName)@{u}"])
        if upstreamCheck.failure {
            return .noRemote
        }

        let remoteRef = "origin/\(localName)"
        let remoteRefExists = !executeGitCommand(
            in: repositoryPath,
            args: ["show-ref", "--verify", "--quiet", "refs/remotes/\(remoteRef)"]
        ).failure
        if !remoteBranches.contains(localName), !remoteRefExists {
            return .noRemote
        }

        let counts = executeGitCommand(in: repositoryPath, args: ["rev-list", "--left-right", "--count", "\(remoteRef)...\(localName)"])
        guard !counts.failure else { return .unknown }
        let parts = counts.output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines)
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else {
            return .unknown
        }

        if ahead == 0, behind == 0 {
            return .upToDate
        }
        if ahead > 0, behind == 0 {
            return .ahead(ahead)
        }
        if ahead == 0, behind > 0 {
            return .behind(behind)
        }
        return .diverged(ahead: ahead, behind: behind)
    }

    private func lastCommitDate(for ref: String, repositoryPath: String) -> Date? {
        let result = executeGitCommand(in: repositoryPath, args: ["log", "-1", "--format=%ct", ref])
        guard !result.failure else { return nil }
        let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let timestamp = TimeInterval(trimmed) else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}
