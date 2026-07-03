import Foundation

final class GitCommandRunner {
    private enum Askpass {
        static let tokenEnvironmentKey = "GITMENUBAR_GIT_ASKPASS_TOKEN"
    }

    var tokenProvider: (() -> String?)?

    func runGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false,
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        runCommand(
            in: directory,
            executable: "/usr/bin/git",
            args: args,
            useAuth: useAuth,
            additionalEnvironment: additionalEnvironment
        )
    }

    func runCommand(
        in directory: String,
        executable: String,
        args: [String],
        useAuth: Bool = false,
        additionalEnvironment: [String: String] = [:]
    ) -> (output: String, failure: Bool) {
        let task = Process()
        task.launchPath = executable
        task.arguments = args
        task.currentDirectoryPath = directory
        var environment = ProcessInfo.processInfo.environment
        var askpassScriptPath: String?

        if useAuth, let token = tokenProvider?() {
            let scriptPath = createAskpassScript()
            if let scriptPath {
                environment["GIT_ASKPASS"] = scriptPath
                environment["GIT_TERMINAL_PROMPT"] = "0"
                environment[Askpass.tokenEnvironmentKey] = token
                askpassScriptPath = scriptPath
            }
        }

        for (key, value) in additionalEnvironment {
            environment[key] = value
        }

        if !environment.isEmpty {
            task.environment = environment
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            cleanupAskpassScript(at: askpassScriptPath)
            return ("Failed to execute git command: \(error.localizedDescription)", true)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        let status = task.terminationStatus

        cleanupAskpassScript(at: askpassScriptPath)

        return (output, status != 0)
    }

    private func createAskpassScript() -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("git-askpass-\(UUID().uuidString).sh").path
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$\(Askpass.tokenEnvironmentKey)"
        """

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
            return scriptPath
        } catch {
            print("Failed to create askpass script: \(error)")
            return nil
        }
    }

    private func cleanupAskpassScript(at path: String?) {
        if let path {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
