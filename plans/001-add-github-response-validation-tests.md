# Plan 001: Add GitHub response validation tests

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: no; the scope does not require a separate review by default.
- **Rationale**: Testes determinísticos e limitados a validação de respostas.
- **Escalate when**: Se o teste exigir mudança de produção ou integração externa.

> Executor instructions: follow the steps, run every verification command, and stop on drift. Include a code review step before committing.
>
> Drift check: `git diff --stat dbdd40e..HEAD -- GitMenuBar/Services/GitHub GitMenuBarTests`

## Status

- Priority: P1
- Effort: S
- Risk: LOW
- Depends on: none
- Category: tests
- Planned at: commit `dbdd40e`, 2026-07-02

## Why this matters

The Thermo Nuclear review extracted GitHub repository response handling from request methods into validation helpers. That simplified `GitHubAPIClient`, but the status-code contract is still only indirectly covered. Add focused tests so future edits cannot silently change delete, create, or visibility error mapping.

## Current state

- `GitMenuBar/Services/GitHub/GitHubAPIClient.swift` contains private validation helpers for repository create/delete/visibility responses.
- `GitMenuBarTests/` has URL/parser/auth tests but no direct tests for GitHub response validation.
- Project uses Xcode synchronized groups, so new Swift test files under `GitMenuBarTests/` are picked up automatically.

## Scope

In scope:
- `GitMenuBar/Services/GitHub/GitHubAPIClient.swift`
- `GitMenuBarTests/GitHubRepositoryResponseValidationTests.swift`

Out of scope:
- Network behavior or `URLSession` injection.
- User-facing copy changes.

## Steps

1. Extract the private response validation helpers into a small internal `GitHubRepositoryResponseValidator` type in `GitHubAPIClient.swift` or a sibling file.
2. Keep `GitHubAPIClient` behavior unchanged by calling the new validator from create/delete/visibility methods.
3. Add XCTest coverage for success and key failures: create `201`, create `422`, delete `204`, delete `403`, visibility `200`, visibility `422`, and unknown JSON message passthrough.
4. Code review step: inspect the diff and confirm no request construction or auth behavior changed.

## Verification

- `xcodebuild test -project GitMenuBar.xcodeproj -scheme GitMenuBar -only-testing:GitMenuBarTests/GitHubRepositoryResponseValidationTests -derivedDataPath .xcode-build-tests` exits 0.
- `make build` exits 0.
- `make lint` exits 0.

## STOP conditions

- If validation helpers cannot be tested without adding network mocks, stop and report.
- If the change requires changing `GitHubAPIError`, stop and report.
