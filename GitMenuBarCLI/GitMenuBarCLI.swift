import ArgumentParser
import Foundation

// Shared Services/Models/Utils roots are compiled into this target alongside GitMenuBarCLI.
// Do not import KeyboardShortcuts, Settings, or other app-only packages here — the CLI
// target must stay headless and build without the menu bar app's UI dependencies.

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
