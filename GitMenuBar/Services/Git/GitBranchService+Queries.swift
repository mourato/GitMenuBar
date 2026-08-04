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

        let currentBranch = await runOnBackground {
            self.executeGitCommand(in: repositoryPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
                .output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let output = await runOnBackground {
            self.executeGitCommand(
                in: repositoryPath,
                args: [
                    "for-each-ref",
                    "--format=%(refname:short)%00%(upstream:short)%00%(committerdate:unix)%00%(upstream:track,nobracket)%00",
                    "refs/heads",
                    "refs/remotes/origin"
                ]
            ).output
        }
        let infos = parseBranchInfoOutput(output, currentBranch: currentBranch)

        await GitExecution.publishOnMainActor(ifCurrent: session) {
            self.branchInfos = infos
        }

        return infos
    }

    func parseBranchInfoOutput(_ output: String, currentBranch: String) -> [BranchInfo] {
        var infos: [BranchInfo] = []
        var localNames = Set<String>()

        for record in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = record.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            let ref = fields[0]
            guard !ref.isEmpty else { continue }
            let upstream = fields[1]
            let date = TimeInterval(fields[2]).map(Date.init(timeIntervalSince1970:))
            let track = fields[3]

            if ref == "origin" {
                continue
            }
            if ref.hasPrefix("origin/") {
                let name = String(ref.dropFirst("origin/".count))
                guard !name.isEmpty, name != "HEAD" else { continue }
                guard !localNames.contains(name) else { continue }
                infos.append(BranchInfo(name: name, isLocal: false, isRemote: true, isCurrent: false, trackingStatus: .noRemote, lastCommitDate: date))
                continue
            }

            localNames.insert(ref)
            infos.append(
                BranchInfo(
                    name: ref,
                    isLocal: true,
                    isRemote: false,
                    isCurrent: ref == currentBranch,
                    trackingStatus: trackingStatus(upstream: upstream, track: track),
                    lastCommitDate: date
                )
            )
        }

        return infos.filter { !$0.isRemote || !localNames.contains($0.name) }
    }

    private func trackingStatus(upstream: String, track: String) -> BranchTrackingStatus {
        guard !upstream.isEmpty else { return .noRemote }
        guard !track.isEmpty else { return .upToDate }
        if track == "gone" {
            return .noRemote
        }

        var ahead: Int?
        var behind: Int?
        for part in track.split(separator: ",") {
            let values = part.split(separator: " ")
            guard values.count == 2, let count = Int(values[1]) else { return .unknown }
            switch values[0] {
            case "ahead": ahead = count
            case "behind": behind = count
            default: return .unknown
            }
        }

        switch (ahead ?? 0, behind ?? 0) {
        case (0, 0): return .upToDate
        case let (ahead, 0): return .ahead(ahead)
        case let (0, behind): return .behind(behind)
        case let (ahead, behind): return .diverged(ahead: ahead, behind: behind)
        }
    }
}
