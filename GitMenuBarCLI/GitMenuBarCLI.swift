import ArgumentParser
import Foundation

@main
struct GitMenuBarCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gitmenubar",
        abstract: """
        GitMenuBar Companion CLI for agent-oriented propose/apply commits.
        Exit codes: 0 ok, 2 not ready, 3 invalid repo, 4 policy rejected, other non-zero operational failure.
        """,
        subcommands: [
            MessageCommand.self,
            CommitCommand.self,
            AtomicCommand.self
        ]
    )
}
