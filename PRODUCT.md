# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Stack

Native macOS app in Swift (Swift 6 language mode, Swift 6.4 compiler) with
SwiftUI and AppKit. A companion CLI shares the app's AI and commit-message
policy for agent-driven commit flows. Requires macOS 15.5 or later and Git on
the system; building from source needs Xcode 27 or later.

## Users

A developer who moves between editor and terminal and wants day-to-day Git
work close at hand: stage, commit, then sync or switch branch with low
ceremony. AI agents also use the companion CLI to create commits.

## Product Purpose

A local-first Git companion that lives in the macOS menu bar and opens a
focused workbench when needed. It lets the user inspect repository state,
review changes, create commits, sync with remotes, manage branches and
worktrees, and monitor several projects without switching to a full-size Git
client.

## Positioning

- Dense, calm, and semantic: a native workbench, not a SaaS dashboard or a
  marketing surface.
- Started as a fork of `saihgupr/GitMenuBar`; it is now an independent app
  with its own workflow, architecture, and feature set.
- Open-source and free to use.

## Operating Context

- The menu-bar status item is the entry point; it opens the main workbench.
- One workbench manages several local projects.
- Repositories can also be opened from Terminal with
  `open -a "GitMenuBar" "/path/to/folder"`.

## Capabilities and Constraints

- Local-first: the main workflow works on the local repository. GitHub and AI
  features are optional integrations, never requirements for everyday use.
- Safe by default: operations that rewrite history, discard changes, delete
  branches, or remove worktrees are explicit and reviewed before they run.
- Capabilities: project workbench, working-tree review, commit workflow,
  AI-assisted commits (generated messages, atomic commit splits), branches and
  worktrees with safe cleanup, remote sync (merge or rebase), history and
  recovery, GitHub integration, command palette, AI usage quotas.
- Cleanup rules:
  - A branch counts as merged when the default branch reaches it or Git
    reports it cherry-equivalent.
  - Clean worktrees may be removed even when their branch is not merged, and
    clean detached worktrees may be removed.
  - Deleting an unmerged branch, alone or with its worktree, requires an
    explicit risk review; unmerged branches are never selected by default.
  - Force Remove Worktree permanently deletes the worktree directory and its
    uncommitted changes but keeps the branch.
  - Project Cleanup is the multi-repo shortcut and keeps its safe eligibility
    contract ([ADR 0005](docs/adr/0005-global-safe-cleanup-boundary.md)).
- Product vocabulary lives in [CONTEXT.md](CONTEXT.md).

## Brand Commitments

- Name: GitMenuBar. App icon: [`Images/icon.png`](Images/icon.png).
- Intended feel: calm, direct feedback.

## Evidence on Hand

- Screenshots in [`Images/Screenshots/`](Images/Screenshots/).
- Static mockups in [`docs/design/`](docs/design/README.md).

## Accessibility & Inclusion

Open: no audience-specific accessibility need is recorded yet. The design
contract in [DESIGN.md](DESIGN.md) covers keyboard, VoiceOver, contrast, and
reduced-motion and transparency behavior.
