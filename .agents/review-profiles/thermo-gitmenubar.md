# GitMenuBar Thermo Review Profile

This is a project-only supplement to `global:thermo-nuclear-code-quality-review`.
It contains no generic review checklist and no model configuration.

## Project invariants

- Preserve performance, reliability, predictable failure behavior, and data
  safety before convenience.
- Treat `NSStatusItem` ownership, status-item click behavior, popover/window
  dismissal, repository switching, branch actions, commit flow, and sync flow
  as product-critical behavior. Load `.agents/skills/menubar/SKILL.md` when a
  diff touches those paths.
- Require a `#Preview` for every new Swift file that renders UI, including
  `View`, `NSViewRepresentable`, and `NSViewControllerRepresentable` files.
- Do not accept orphaned UI, logic, assets, or stale resources introduced by a
  change; prove removals with `rg`, target wiring, and the runtime path.
- Treat changed Swift lint findings as mandatory. Use `make agent-check` during
  implementation and `make lint && make test` as the merge gate.

## Routing boundary

Use `.agents/skills/delivery-workflow/SKILL.md` for risk lanes, command
routing, validation depth, logs, and Git evidence. Use the narrowest domain
skill for technical behavior. This profile only adds GitMenuBar-specific
acceptance criteria to the global thermo review.
