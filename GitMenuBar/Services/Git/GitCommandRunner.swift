import Foundation

final class GitCommandRunner {
    var tokenProvider: (() -> String?)?

    private var askpassScriptPath: String?

    func runGitCommand(
        in directory: String,
        args: [String],
        useAuth: Bool = false
    ) -> (output: String, failure: Bool) {
        runCommand(in: directory, executable: "/usr/bin/git", args: args, useAuth: useAuth)
    }

    func runCommand(
        in directory: String,
        executable: String,
        args: [String],
        useAuth: Bool = false
    ) -> (output: String, failure: Bool) {
        let task = Process()
        task.launchPath = executable
        task.arguments = args
        task.currentDirectoryPath = directory

        if useAuth, let token = tokenProvider?() {
            var env = ProcessInfo.processInfo.environment
            let scriptPath = createAskpassScript(token: token)
            if let scriptPath {
                env["GIT_ASKPASS"] = scriptPath
                env["GIT_TERMINAL_PROMPT"] = "0"
                task.environment = env
                askpassScriptPath = scriptPath
            }
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            cleanupAskpassScript()
            return ("Failed to execute git command: \(error.localizedDescription)", true)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        let status = task.terminationStatus

        cleanupAskpassScript()

        return (output, status != 0)
    }

    private func createAskpassScript(token: String) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("git-askpass-\(UUID().uuidString).sh").path
        let scriptContent = "#!/bin/bash\necho \"\(token)\""

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
            return scriptPath
        } catch {
            print("Failed to create askpass script: \(error)")
            return nil
        }
    }

    private func cleanupAskpassScript() {
        if let path = askpassScriptPath {
            try? FileManager.default.removeItem(atPath: path)
            askpassScriptPath = nil
        }
    }
}
