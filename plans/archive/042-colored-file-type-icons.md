# Plan 042: Add colored File Type Icons for Diff Trees

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 42cde45..HEAD -- GitMenuBar/Components/History/FileTypeSymbol.swift GitMenuBar/Components/History/ChangedFilesSummaryView.swift GitMenuBar/Components/WorkingTree/ GitMenuBar/Resources/ plans/040-commit-details-changed-files-summary.md plans/041-working-tree-diff-tree.md plans/042-colored-file-type-icons.md plans/README.md CONTEXT.md .agents/overlays/reference-apps.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/040-commit-details-changed-files-summary.md (041 recommended first so both surfaces benefit)
- **Category**: direction
- **Planned at**: commit `42cde45`, 2026-07-26

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: `yes` — independent workstream once 040 (+ ideally 041) UI hooks exist; do not parallelize with active edits to the same icon call sites
- **Reviewer required**: `yes` — license/asset provenance and appearance in light/dark
- **Rationale**: Asset/legal choices plus theme tokens; not a mechanical SF Symbol map.
- **Escalate when**: Vendoring a large third-party icon font, adding network-downloaded icons, or replacing the Diff Tree layout.

## Why this matters

Phase-1 Diff Trees use SF Symbols. T3 Code’s distinctive File Type Icons
(Swift orange mark, Markdown green “M”, etc.) come from `@pierre/trees` plus
light/dark color tokens in `PierreEntryIcon.tsx`. GitMenuBar should offer a
**license-safe** colored icon set that plugs into the existing File Type Icon
call sites without changing navigation or staging behavior.

## Current state

- Plan 040 introduces `FileTypeSymbol` (SF Symbol names).
- T3 reference (Nightly clone):  
  `~/Documents/Projects/References/T3Code/apps/web/src/components/chat/PierreEntryIcon.tsx`  
  `~/Documents/Projects/References/T3Code/apps/web/src/pierre-icons.ts`  
  Dependency: `@pierre/trees@1.0.0-beta.4` (verify license **before** copying
  any SVG/path data).
- T3 Code itself is MIT; that does **not** automatically clear `@pierre/trees`.
- Reference-apps overlay documents this under **T3Code**.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 42cde45..HEAD -- <in-scope paths>` | empty or understood drift |
| Debug build | `make build` | exit 0 |
| Tests | `make test` | `Tests passed` |
| Agent gate | `make agent-check` | pass |

## Suggested executor toolkit

- `global:apple-design`, `global:accessibility-audit` (+ overlays) for contrast.
- `global:reference-apps` for T3 color token comparison.
- Local `security-credentials` only if bundling unfamiliar binary assets
  (unlikely).

## Scope

**In scope**:
- License/provenance decision recorded in the PR description (and a short
  comment or `docs/file-type-icons.md` if assets are
  added)
- Icon assets **or** Swift-drawn shapes under an agreed approach (see steps)
- Replacement/adapter for `FileTypeSymbol` used by Commit Details + working
  tree Diff Trees
- Light/dark color tokens for common languages used in this repo (Swift,
  Markdown, JSON, YAML, shell, images, generic)
- Unit test for extension → icon identity mapping (no pixel tests required)
- `plans/README.md` status row
- Optional one-line touchpoint update in `.agents/overlays/reference-apps.md`

**Out of scope**:
- Re-layout of Diff Tree / Compact Preview
- New file-open behaviors
- Shipping the entire Pierre complete set “because T3 has it”
- NPM packaging or runtime JS bridges

## Git workflow

- Prefer a dedicated branch after 040/041 merge to reduce conflict on icon call
  sites.
- Do not push/PR unless asked.

## Steps

### Step 1: License gate (mandatory first)

Determine whether `@pierre/trees` (and any SVG you intend to copy) allows use
in GitMenuBar. Record SPDX license + source URL in the PR.

- If **not** clearly permissible: implement an original SF Symbol + tint
  strategy or original vector assets — do **not** paste T3/Pierre path data.
- If permissible: vendor only the subset of icons GitMenuBar needs; keep
  attribution as the license requires.

**Verify**: PR notes contain license conclusion; `rg -n "pierre|Pierre|@pierre" GitMenuBar` shows only intentional attribution comments if any

### Step 2: Icon resolver API

Keep a single resolver used by both surfaces, e.g. extend `FileTypeSymbol` into
`FileTypeIcon` that returns:

- kind/token (swift, markdown, json, …)
- light + dark colors (use semantic/adaptive `Color` where possible)
- image/source (asset name, SF Symbol fallback, or drawn template)

Fallback chain: specific name → extension → generic doc.

**Verify**: `make build` → exit 0

### Step 3: Wire into Diff Trees + contrast check

Replace SF-only Image views in Changed Files Summary and working-tree file
rows. Ensure:

- Status letters remain readable (041).
- Icons are decorative (`accessibilityHidden` / combined parent label).
- Increase Contrast / dark mode still readable (prefer slightly brighter dark
  tokens like T3’s pairs, but map into AppKit/SwiftUI colors — do not hardcode
  web-only CSS).

Add resolver unit tests for `.swift`, `.md`, `Package.swift` / known filenames
if special-cased, and unknown `.foo`.

**Verify**: `make test` → `Tests passed`  
**Verify**: `make agent-check` → pass

### Step 4: Manual appearance checklist

- [ ] Swift file shows distinct orange-leaning mark in light and dark
- [ ] Markdown distinguishable from plain text
- [ ] Unknown extension still shows a calm generic icon
- [ ] No layout shift vs SF Symbol phase (row height stable)

## Test plan

- Resolver mapping tests only.
- No screenshot golden files unless the repo later adds a snapshot harness.

## Done criteria

- [ ] License gate documented and followed
- [ ] Colored icons appear in Commit Details Diff Tree
- [ ] Working-tree Diff Tree uses the same resolver when Plan 041 has landed;
      if 041 is not merged, Commit Details alone is acceptable but README must
      note the gap
- [ ] SF Symbol fallback remains for unknown types
- [ ] `make build`, `make test`, `make agent-check` pass
- [ ] `plans/README.md` 042 → DONE

## STOP conditions

- License of intended assets is unclear or non-compliant.
- Scope expands to full Pierre sprite parity without product need.
- Diff Tree interaction code is rewritten “to make icons fit.”

## Maintenance notes

- When adding a new language icon, update resolver tests and the small curated
  set — do not import entire icon packs casually.
- Reviewer focus: provenance, dark/light contrast beside green/red diff stats,
  decorative-icon a11y.
