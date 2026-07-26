import ArgumentParser
import Foundation

enum CompanionCLIRuntime {
    private static let service = CompanionCLIService()

    static func serviceInstance() -> CompanionCLIService {
        service
    }

    static func finishWithError(_ error: CompanionCLIService.Error, jsonPreferred: Bool) throws -> Never {
        if jsonPreferred {
            let payload = CompanionCLIErrorPayload(
                error: error.localizedDescription ?? "Command failed.",
                exitCode: error.cliExitCode
            )
            if let json = try? CompanionCLIEncoder.encodeJSON(payload) {
                print(json)
            }
        }
        FileHandle.standardError.writeData(Data("\(error.localizedDescription ?? "Command failed.")\n".utf8))
        throw ExitCode(error.cliExitCode)
    }

    static func printJSON(_ json: String) {
        print(json)
    }

    static func printPlain(_ text: String) {
        print(text)
    }
}

private extension FileHandle {
    func writeData(_ data: Data) {
        write(data)
    }
}
