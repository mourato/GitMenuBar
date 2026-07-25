# Plan 026: Add Workbench button variants and adopt on main panel + popovers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bb03dcc..HEAD -- .interface-design/system.md GitMenuBar/Components/Common/ GitMenuBar/Pages/MainMenu/ GitMenuBar/Components/Projects/ GitMenuBar/Components/Branches/BottomBranchSelector.swift GitMenuBar/Components/Branches/BranchSelectorPopover.swift GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift GitMenuBar/Components/Common/CommitComposer.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/025-workbench-system-and-token-rename.md
- **Category**: dx
- **Planned at**: commit `bb03dcc`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `no` — shared control API + call-site adoption
- **Reviewer required**: `no` by default; yes if accessibility labels regress or Primary commit shortcut breaks
- **Rationale**: Visual/API design judgment across controls, but bounded to main panel + popovers.
- **Escalate when**: scope creeps into Settings, branch management sheet, or confirmation dialogs.

## Why this matters

The main panel mixes `.borderless`, `.plain`, `.borderedProminent`, `.link`, and `PressableButtonStyle` without a shared vocabulary. Users learn controls by pattern; fragmentation raises cognitive load. `.interface-design/system.md` defines Primary / Secondary / Ghost / Icon / Destructive / Row — this plan implements that kit and adopts it where developers live daily (main panel + attached popovers).

## Current state

After Plan 025, tokens are `Workbench*`. Today’s exemplars (names may already be `Workbench*` when you execute):

```26:47:GitMenuBar/Components/Common/CommitComposer.swift
            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    // ...
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isPrimaryButtonDisabled ? .gray.opacity(0.75) : nil)
            .disabled(isPrimaryButtonDisabled)
            .keyboardShortcut(.defaultAction)
```

```55:67:GitMenuBar/Pages/MainMenu/BranchManagementControlsView.swift
            if canShowAtomicCommits {
                Button("Atomic Commits") {
                    onAtomicCommits()
                }
                .buttonStyle(.borderless)
                .font(MacChromeTypography.detail) // → WorkbenchTypography.detail after 025
            }

            Button("Manage…") {
                onManage()
            }
            .buttonStyle(.borderless)
```

```12:22:GitMenuBar/Components/Common/MainMenuHeaderIconButton.swift
        Button(action: action) {
            Image(systemName: systemImage)
                .font(MacChromeTypography.body)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous)
                        .fill(isHovered ? MacChromePalette.hoverFill() : Color.clear)
                )
        }
        .buttonStyle(.plain)
```

```23:37:GitMenuBar/Components/Common/RepositoryOptionsPopoverView.swift
            Button(action: onToggleVisibility) { actionRow(...) }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDeleteRepository) { actionRow(...) }
            .buttonStyle(.plain)
```

Note: options rows currently use a **permanent** `hoverFill()` background — idle should be clear; hover/focus applies fill (system.md Row variant).

Locked variant table: see `.interface-design/system.md` § Button variants.  
Press style already exists as `PressableButtonStyle` in the metrics file — reuse it inside the kit.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat bb03dcc..HEAD -- <paths>` | understood |
| Prove 025 landed | `rg -n 'enum WorkbenchMetrics' --glob '*.swift' GitMenuBar` | match |
| Incremental | `make agent-check` | exit 0 |
| Full | `make lint && make test` | exit 0 |

## Suggested executor toolkit

- `apple-design`, `accessibility-audit`, `macos-app-engineering`, `swift-conventions`
- `.interface-design/system.md` (authoritative)
- AGENTS.md: new UI files need `#Preview`

## Scope

**In scope (create)**

- `GitMenuBar/Components/Common/WorkbenchButtonStyles.swift` — shared styles / thin wrappers for:
  - Primary (prominent + optional large + defaultAction support left to call site)
  - Secondary
  - Ghost
  - Icon (min hit `WorkbenchMetrics.iconHitTarget`)
  - Destructive (role-aware)
  - Row (plain + hover/selected fills; idle clear)
- `#Preview` matrix showing all variants
- Refactor `MainMenuHeaderIconButton` to use Icon variant (or become a thin wrapper)

**In scope (adopt — main panel + popovers only)**

- `CommitComposer.swift` — Primary
- `BranchManagementControlsView.swift` — Ghost for Atomic / Manage
- `MainMenuHeaderView.swift` / `MainMenuHeaderIconButton.swift` — Icon
- `BottomBranchSelector.swift` — keep Pressable; align with Row/Icon patterns as appropriate (branch chip may stay custom but must use Workbench tokens + press)
- `BranchSelectorPopover.swift` / `NewBranchButton.swift` — Row / Secondary as fits
- `ProjectSelectorPopover.swift` / `RecentPathRow.swift` — Row / press consistency
- `RepositoryOptionsPopoverView.swift` — Row + Destructive; **fix permanent fill**
- `InlineStatusBannerView.swift` — Ghost Dismiss
- `MainMenuSupportViews.swift` / create-repo suggestion link — map to Ghost or Secondary (not ad-hoc `.link` unless navigating externally)
- `MainMenuCommandPalette.swift` rows — Row selected/hover fills via `WorkbenchPalette`

**Out of scope**

- Settings panes, AI provider sheets, AtomicCommitReviewSheet, BranchManagementSheet, Create/Rename/Pull sheets
- `ConfirmationDialogsModifier.swift` mass restyle
- Working-tree per-file hover policy / hit targets (Plan 027) — do not change opacity/hover reveal rules here except if a shared Icon style is applied without changing visibility policy
- Footer weight / moving Atomic or Manage out of the footer
- Plan 029 implementation

## Git workflow

- Branch: `feat/026-workbench-button-variants`
- Commit example: `feat(ui): add Workbench button variants for main panel`
- No push unless asked

## Steps

### Step 1: Confirm Plan 025

**Verify**: `rg -n 'MacChromeMetrics' --glob '*.swift' GitMenuBar` → no matches; `WorkbenchMetrics` exists

### Step 2: Implement `WorkbenchButtonStyles.swift`

Implement styles matching `.interface-design/system.md`. Reuse `PressableButtonStyle` / `WorkbenchMotion` for press. Icon variant frame ≥ `iconHitTarget`.

**Verify**: file exists + `#Preview` compiles via `make agent-check` after wiring one call site, or build once styles are referenced

### Step 3: Adopt on listed main-panel / popover files

 mechanize: each Button in Scope gets exactly one variant. Fix Repository Options idle background.

**Verify**: `make agent-check` → exit 0

### Step 4: Accessibility smoke

Ensure header Icon buttons keep `accessibilityLabel` / `accessibilityHint`. Primary commit keeps `.keyboardShortcut(.defaultAction)`.

**Verify**: `make lint && make test` → exit 0; update README 026 → DONE

## Test plan

- Prefer SwiftUI previews for variant matrix (required on new file).
- No mandatory new XCTest unless an existing snapshot/helper covers buttons (none assumed).
- Manual checklist: Commit still default action; Manage/Atomic still clickable; repo options hover only on hover; gear still opens Settings.

## Done criteria

- [ ] `WorkbenchButtonStyles.swift` exists with previews for all six variants
- [ ] Main-panel + listed popover buttons use the kit (no stray one-off styles for those call sites)
- [ ] Repository options rows idle background is clear
- [ ] `make lint && make test` exit 0
- [ ] README 026 DONE
- [ ] Sheets/Settings untouched

## STOP conditions

- Plan 025 not merged / `MacChrome*` still present
- Adoption seems to require rewriting BranchManagementSheet or Settings
- Primary commit loses keyboard default action
- Changing working-tree hover reveal behavior “while here”

## Maintenance notes

- Sheets/Settings adoption is **Plan 029** (stub only in README until authored).
- Reviewers: new buttons must cite a variant; reject raw `.borderless` sprawl on main panel.
- Row selected fill must use `WorkbenchPalette.selectedFill()`, not ad-hoc accent opacities.
