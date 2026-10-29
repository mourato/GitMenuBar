# Commit inspector polish (2026-10-29)

Planned at commit `fa92af4`. Goal: premium look for commit details in the main
window. The side panel becomes a split column, not an overlay. Reference
mockup was reviewed in chat; the decisions it encodes are restated in each plan.

| Plan | Scope | Depends on | Suggested executor |
|---|---|---|---|
| 001 | Selected history row keeps its title | none | OpenCode free model |
| 002 | Side panel as split column + window minimum width | none | Codex `gpt-5.6-luna`, reasoning `xhigh` |
| 003 | Commit detail header hierarchy + body without subject | 002 | Antigravity Gemini Flash 3.8, `high` |
| 004 | Commit detail actions + overflow menu | 003 | Antigravity Gemini Flash 3.8, `high` |
| 005 | Changed files as a vertical list | 002 | OpenCode free model |

Order: 001 and 002 can run in parallel. 003 then 004 (same file). 005 can run
in parallel with 003/004 (different file).

Rejected for this batch: sticky date headers in history; per-file status
letters (M/A/D) because `CommitFileChange` has no status field.

Rules every plan inherits:

- Read `AGENTS.md`, `docs/agents/project-workflow.md`, and `CODING_STANDARDS.md`.
- Visible labels never end with an ellipsis (`…` or `...`).
- Use `WorkbenchMetrics`, `WorkbenchTypography`, `WorkbenchPalette` tokens.
  Add a token only when no existing one fits.
- Respect Reduce Motion; read `docs/agents/motion.md` before touching animation.
- Run `make check-preview` and `make lint-changed` before handoff; run
  focused tests named in the plan.

## Contract sources

- `docs/ui.md` and `docs/adr/0021-side-panel-split-column.md` describe the
  target. When a plan and `docs/ui.md` disagree, stop and report.
- Reference image: `docs/design/commit-inspector-2026-10-29.png`; read
  `docs/design/README.md` for its known differences.
- History rows show subject, short hash, and time. Author is only in details.

## UI review rubric and evidence

The coordinator reviews every unit against this list. Any item failing is a
rejection.

1. Values come from `WorkbenchMetrics`, `WorkbenchTypography`,
   `WorkbenchPalette`, `WorkbenchMotion`. No raw numbers except those this
   plan states.
2. One accent per window: Commit button and focused selection only.
3. No shadow on inline surfaces (side panel, cards, rows).
4. No visible label ends with `…` or `...`.
5. Icon hit areas at least 28 × 28 pt; text buttons use shared styles.
6. One vertical scroll owner per surface; no nested `ScrollView`.
7. No `matchedGeometryEffect` id shared by two visible views.
8. Animation has a Reduce Motion path (`adaptiveMotion()` or the shared
   motion tokens).
9. Every icon-only control has an accessibility label and `.help`.
10. Light, Dark, and Increase Contrast stay readable.

Evidence each unit hands off:

- `#Preview` blocks for the changed views with named states. Use the cases
  that apply: default, long subject (3+ lines), merge commit, no body,
  1 file, 30 files, long path, no GitHub remote.
- Screenshots of those previews (light and dark) or of the running app at
  minimum window width, saved under `.xcode-build/ui-evidence/<plan>/`
  (ignored path; do not commit them).
- Commands run and their exact result.
- A short list of any rubric item you could not satisfy, with the reason.
