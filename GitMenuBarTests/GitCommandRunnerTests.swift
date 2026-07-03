@testable import GitMenuBar
import XCTest

final class GitCommandRunnerTests: XCTestCase {
    func testAskpassScriptDoesNotPersistTokenInTemporaryFile() {
        let runner = GitCommandRunner()
        runner.tokenProvider = { "super-secret-token" }

        let result = runner.runCommand(
            in: FileManager.default.temporaryDirectory.path,
            executable: "/bin/sh",
            args: [
                "-c",
                """
                script_content="$(cat "$GIT_ASKPASS")"
                case "$script_content" in
                  *super-secret-token*) exit 11 ;;
                esac
                [ "$("$GIT_ASKPASS")" = "super-secret-token" ] || exit 12
                printf '%s' "$GIT_ASKPASS"
                """
            ],
            useAuth: true
        )

        XCTAssertFalse(result.failure, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.output))
    }
}
