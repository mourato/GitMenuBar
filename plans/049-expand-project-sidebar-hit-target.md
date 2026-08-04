# Plan 049: Make the entire Projects sidebar row select its project

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2beedd..HEAD -- GitMenuBar/Components/Projects/ProjectsSidebarView.swift .interface-design/system.md`
> If either in-scope source/design file changed since this plan was written,
> compare the "Current state" excerpts against the live code before
> proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `b2beedd`, 2026-08-04

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: yes — independent of the Git refresh plans
- **Reviewer required**: no — one SwiftUI hit-testing change with no state,
  persistence, navigation, or dependency change
- **Rationale**: The row is already a real `Button` and already has the right
  visual layout; the smallest safe fix is to make its rectangular layout
  explicit to hit testing while retaining the existing context menu.
- **Escalate when**: the row contains a nested interactive control, the
  context menu is not attached to the same row after the change, or the fix
  requires changing sidebar layout, selection state, or project persistence.

## Why this matters

The project name is currently the only reliable selection target in practice,
although the row visually represents one project and its context menu already
responds across a larger area. Developers switch projects frequently; making
the whole row clickable removes a needless precision requirement with almost
no implementation risk. The context menu must continue to work on the same
row, including when the sidebar is collapsed.

## Current state

- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift:170-208` renders
  each project as a plain `Button`, but the label has no explicit
  `contentShape`:

  ```swift
  private func row(_ snapshot: ProjectStatusSnapshot) -> some View {
      Button { onSelect(snapshot.project.path) } label: {
          HStack(spacing: 7) { /* status, name, branch, spacer */ }
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(selectionBackground)
      }
      .buttonStyle(.plain)
      .contextMenu { /* Rename, Reveal, Stop Monitoring, Remove */ }
  }
  ```

- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift:215-224`
  defines the sidebar width as 220–360 points when expanded, so the intended
  hit target is the full row width, not only the text's intrinsic width.
- The preview at `ProjectsSidebarView.swift:226-236` already supplies the
  required environment objects. Do not create another preview file.
- `.interface-design/system.md` defines row controls as real SwiftUI Buttons
  and requires hit areas of at least 28×28 points; the visible row can remain
  dense while its hit area is larger.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Source inspection | `rg -n 'private func row|buttonStyle|contentShape|contextMenu' GitMenuBar/Components/Projects/ProjectsSidebarView.swift` | the row has one selection Button, one plain style, one rectangular hit shape, and one context menu |
| Preview coverage | `make check-preview` | exit 0 |
| Scoped validation | `make agent-check` | changed Swift lint passes and the Debug build succeeds |
| Guidance validation | `make guidance-check` | exit 0 |
| Merge gate | `make lint && make test` | both commands exit 0 |

## Suggested executor toolkit

- Use `global:swiftui-expert-skill` for SwiftUI hit testing and Button
  composition.
- Use `global:swiftui-accessibility-audit` because the row's visible label,
  VoiceOver label, and keyboard activation must remain intact.
- Use `global:swift-conventions` for the final Swift formatting/lint check.

## Scope

**In scope** (the only source/design files to modify):

- `GitMenuBar/Components/Projects/ProjectsSidebarView.swift`

Plan metadata files:

- `plans/049-expand-project-sidebar-hit-target.md`
- `plans/README.md`

**Out of scope** (do not touch):

- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift` — selection behavior is
  already routed through `onSelect`; do not change refresh orchestration here.
- `GitMenuBar/Services/Git/ProjectMonitorStore.swift` and persistence stores —
  row hit testing must not change monitoring or recents semantics.
- Context-menu actions, project ordering, row appearance, sidebar width,
  keyboard navigation, localization, or a new row/button abstraction.

## Git workflow

- Branch: `advisor/049-expand-project-sidebar-hit-target` (or the repository's
  current branch convention if the operator already supplied an isolated
  implementation branch).
- Keep the change to one logical commit if committing is requested; use the
  repository's Conventional Commit style, e.g.
  `fix(ui): expand project sidebar hit target`.
- Do not push or open a PR unless the operator explicitly instructs it.

## Steps

### Step 1: Give the existing row Button a full rectangular hit target

In `ProjectsSidebarView.row(_:)`, preserve the current `Button`, its HStack,
padding, selection background, `.buttonStyle(.plain)`, context menu, and
accessibility label. Add an explicit rectangular `contentShape` to the
full-width label after its padding/frame, and ensure the Button itself remains
full-width when the sidebar is expanded. The target shape must include the
blank space between the status dot, project text, branch text, and trailing
edge; it must not add a second nested Button or move the context menu to a
different view.

Use the existing `frame(maxWidth: .infinity, alignment: .leading)` rather than
adding fixed row widths. The collapsed row must keep its current compact
geometry while the whole visible collapsed cell remains selectable.

**Verify**: `rg -n 'contentShape\(Rectangle\(\)\)|\.contextMenu|\.buttonStyle\(\.plain\)' GitMenuBar/Components/Projects/ProjectsSidebarView.swift` → one rectangular hit shape and the existing plain Button/context-menu modifiers are present.

### Step 2: Validate selection and context-menu behavior

Run `make check-preview` and `make agent-check`. In the Debug app, exercise
each of these points on an expanded row: status dot, blank leading padding,
project name, branch subtitle, blank trailing area, and the row boundary.
Each primary click must select the project. Right-clicking the same areas must
still open the existing native context menu without selecting a different
project or losing Rename, Reveal in Finder, Stop Monitoring, and Remove Project.
Repeat once with the sidebar collapsed.

**Verify**: both commands exit 0 and the manual pass confirms full-row primary
selection plus the unchanged context menu.

### Step 3: Run the repository gates

Run `make guidance-check`, then `make lint && make test`. Update the Plan 049
row in `plans/README.md` only after the implementation and validation pass.

**Verify**: all commands exit 0 and `git status --short` shows only the
intended source file plus the plan/index metadata.

## Test plan

- No new unit test is required: SwiftUI hit testing is a visual/interaction
  concern, and the existing `#Preview` is the structural seam.
- `make check-preview` confirms the changed UI file keeps preview coverage.
- Manual verification must test both primary click and context-menu gestures;
  neither gesture may be replaced by the other.
- `make agent-check` and the final lint/test gate cover compile and regression
  safety.

## Done criteria

- [ ] Clicking any point inside an expanded project row selects that project.
- [ ] Clicking any point inside a collapsed project cell selects that project.
- [ ] Right-click context menus still open from the full row and retain all
      four existing project actions.
- [ ] No nested interactive control, fixed width, or new abstraction was
      introduced.
- [ ] `make check-preview`, `make agent-check`, `make guidance-check`,
      `make lint`, and `make test` exit 0.
- [ ] No files outside the in-scope list are modified.
- [ ] `plans/README.md` status row for Plan 049 is updated only after done.

## STOP conditions

Stop and report instead of improvising if:

- `row(_:)` no longer uses the Button/context-menu structure shown above.
- The full-width hit shape causes a nested button, prevents the context menu,
  or changes the row's visible width/selection appearance.
- Accessibility loses the project name, button role, or keyboard activation.
- The fix appears to require changing project selection, monitoring,
  persistence, or a shared button style.
- `make check-preview`, `make agent-check`, or the final lint/test gate fails
  twice after a reasonable scoped correction.

## Maintenance notes

- Keep the hit shape attached to the row's existing Button as future row
  content is added; do not make only the text or status indicator clickable.
- If a future row gains an action button, keep it as a sibling control rather
  than nesting it inside the selection Button; reserve separate hit areas for
  the two actions.
