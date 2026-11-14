# Lucide Icons

Interface icons come from one pack: [Lucide](https://github.com/lucide-icons/lucide),
vendored as a pinned `lucide-static` SVG subset. Rationale lives in
[ADR 0025](adr/0025-lucide-interface-icon-pack.md); the epic table lives in
[mourato/GitMenuBar#22](https://github.com/mourato/GitMenuBar/issues/22).

| Attribute | Value |
|-----------|-------|
| **SPDX** | `ISC` |
| **Source** | npm registry tarball `lucide-static@1.72.0` via `scripts/sync-lucide-icons.sh` |
| **Vendored** | 83 SVGs in `GitMenuBar/Resources/LucideIcons/` (epic-table subset only) |
| **Permissibility** | Clearly permissible for redistribution and derivative use under ISC |

## Using icons

```swift
LucideIconView(name: .search)
Label(lucide: .settings, "Settings")
NSImage(lucide: .gitBranch) // AppKit toolbar / status item, template-tinted
```

- Pick a `LucideIconName` case. Never write a Lucide file name or an SF Symbol
  string at a call site.
- Color comes from the context (`foregroundStyle`, `.tint`, template
  rendering). Lucide is outline-only; there are no `.fill` variants.
- The wrapper's `questionmark` fallback is the single sanctioned `systemName:`
  in the codebase. Everything else fails `make lint`.

## Adding or updating icons

1. Add the kebab-case name to the `ICONS` list in `scripts/sync-lucide-icons.sh`.
2. Run `scripts/sync-lucide-icons.sh`. It re-downloads the pinned subset and
   regenerates `GitMenuBar/Components/Common/LucideIconName.swift` — never edit
   that file by hand.
3. Check the `#Preview` catalog in `LucideIconView.swift` (Light and Dark) and
   run `make lint && make test`.

To move to a newer `lucide-static`, bump `LUCIDE_VERSION` in the script,
re-run it, and review the SVG diff before committing.

## Out of scope (do not vendor)

- Brand logos (`ProviderIcon-*`). Lucide refuses brand icons by policy.
- `@pierre/trees` file-type artwork (`FileTypeIcon.swift`) — illustration, not
  interface iconography. See `docs/file-type-icons.md`.
- `MenuBarIcon` / `AppIcon` — product identity.
