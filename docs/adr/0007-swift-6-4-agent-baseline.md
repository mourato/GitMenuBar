# ADR 0007: Swift 6.4 agent baseline

## Decision

GitMenuBar uses Swift 6 language mode (`SWIFT_VERSION = 6.0`) compiled by the
Swift 6.4/Xcode 27 toolchain. Every app, test, and companion CLI Debug and
Release configuration explicitly uses complete strict concurrency checking and
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. UI and lifecycle types opt into
`@MainActor` where they own AppKit/SwiftUI state; Git and CLI work remains
nonisolated unless a concrete ownership boundary requires otherwise.

SwiftFormat 0.62.1 formats Swift 6 language-mode syntax with four-space
indentation. SwiftLint runs in strict mode, covers app/tests/CLI, and does not
accept warning debt. Existing complex callback/parsing seams have narrow,
temporary `cyclomatic_complexity` exceptions; the owning migration reviewer
removes each after extracting a behavior-preserving helper.

## Agent command tiers

- `make agent-check`: changed Swift lint plus Debug build.
- `make lint-changed`: changed SwiftFormat and strict SwiftLint.
- `make lint && make build && make test`: full merge gate.
- `make guidance-check` and `make check-preview`: policy and UI coverage gates.

## Rewrite and exception policy

Migration edits must be behavior-preserving and tied to a compiler diagnostic,
formatter result, or selected lint rule. Prefer explicit actor ownership,
Sendable value boundaries, and structured concurrency. Do not use broad
`@preconcurrency`, `@unchecked Sendable`, unsafe isolation, disabled lint
rules, or fake awaits as migration shortcuts. Temporary lint exceptions must
name the path/rule, have an owner in the review, and state their removal
condition.

Future Swift/Xcode upgrades update this ADR, project settings, formatter/lint
configs, scripts, overlays, and the command evidence together.
