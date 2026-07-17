# Code review: Plan 020

- **Reviewed scope**: temporary-repository integration fixtures, observable cleanup outcomes, architecture terminology, and plan status
- **Reviewer**: thermo-nuclear-code-quality-review with GitMenuBar review profile
- **Final verdict**: APPROVED after fixes

## Findings

### [HIGH] Keep integration tests isolated from developer repositories

- **Area**: test safety and reproducibility
- **Issue**: worktree tests must not depend on a checkout, remote account, or network state.
- **Resolution**: the new suite creates repositories below the system temporary directory, configures an isolated test identity, uses only local Git commands, and removes all created worktrees and directories in `defer` cleanup blocks.

### [HIGH] Assert observable Git and filesystem state

- **Area**: regression coverage
- **Issue**: result messages alone cannot prove that refs and linked checkout directories changed correctly.
- **Resolution**: integration tests assert branch refs with `show-ref`, directory existence with `FileManager`, and per-item success/skipped results. The fixture covers merged and unmerged branches, clean and dirty linked worktrees, and detached worktrees.

### [MEDIUM] Preserve partial-batch behavior

- **Area**: recoverability
- **Issue**: a skipped dirty worktree must not prevent later eligible cleanup targets from completing.
- **Resolution**: the integration test orders a merged branch, a dirty worktree, and a clean worktree, then verifies two successes, one skip, the remaining dirty directory, and the removed branch/ref.

### [MEDIUM] Document the safety contract in repository architecture guidance

- **Area**: maintainability and future changes
- **Issue**: worktree, working-tree, merge, remote-ref, and safe-cleanup semantics were not previously written down.
- **Resolution**: `docs/ARCHITECTURE.md` now defines the terminology, graph-based merge rule, last-fetch remote behavior, ineligible states, explicit target boundaries, revalidation, serial execution, and no-force/no-stash/no-checkout invariants.

## Review checks

- Temporary fixtures use only paths created by the test and do not touch the developer checkout.
- Cleanup uses force only in test teardown, never in production cleanup code.
- No network or personal GitHub account is required; remote behavior remains covered by the existing local bare-repository tests.
- The new test file has no SwiftFormat or SwiftLint violations.
- No manual UI session was available in the CLI validation environment; UI safety and accessibility remain covered by the Plan 018/019 review and previews.

## Validation

- `make agent-check`: passed; the new integration test linted cleanly and Debug build succeeded.
- `make test`: passed twice consecutively.
- `make guidance-check`: passed.
- `git diff --check`: passed.
- `make lint`: blocked by pre-existing SwiftFormat violations in untouched `GitMenuBarTests/MainMenuCommandPaletteResolverTests.swift`, `GitMenuBar/Pages/MainMenu/HistorySectionView.swift`, `GitMenuBar/Pages/Settings/SettingsPage.swift`, and `GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift`.

No unresolved Critical, High, Medium, or Low findings remain in the Plan 020 diff.
