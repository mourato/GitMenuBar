# ADR 0025: Lucide as the single interface icon pack (infra)

Status: Accepted
Date: 2026-11-13
Related: [Epic #22](https://github.com/mourato/GitMenuBar/issues/22) (adopt Lucide),
[docs/file-type-icons.md](../file-type-icons.md) (Pierre precedent),
[docs/lucide-icons.md](../lucide-icons.md) (catalog maintenance)

## Context

The app names ~70 SF Symbols as bare strings (`systemName:` / `systemImage:` /
`systemSymbolName:`) across ~60 files, with no type safety and no guaranteed
visual consistency. Any new screen invents its own symbol names, and nothing
stops two screens from drawing the same action two ways.

## Decision

- Every interface icon comes from the Lucide pack
  ([lucide-icons/lucide](https://github.com/lucide-icons/lucide), ISC),
  vendored as a pinned `lucide-static` SVG subset in
  `GitMenuBar/Resources/LucideIcons/` plus a generated `LucideIconName` enum.
  Render only through `LucideIconView`, `Label(lucide:)`, or
  `NSImage(lucide:)`; color always comes from the context, never the icon.
- A full SPM dependency is rejected: it would ship ~140 thousand generated
  lines for ~64 icons, with no AppKit toolbar/status-item story. Local SVGs
  rendered through AppKit follow the `FileTypeIconRenderer` precedent and keep
  the same cache + template-tint behavior.
- Explicitly out of the catalog: `ProviderIcon-*` brand logos (Lucide refuses
  brand icons by policy, so there is no pack equivalent), `@pierre/trees`
  file-type artwork in `FileTypeIcon.swift` (illustration, not interface
  iconography), `MenuBarIcon` / `AppIcon` (product identity), and the `M`/`D`/`U`
  letters in `GitModels.swift` (text, not icons).
- New `systemName:` / `systemImage:` / `systemSymbolName:` uses outside
  `LucideIconView.swift` fail `make lint` (rule `lucide_no_system_image`).
  The ~60 legacy call sites are grandfathered in the rule's `excluded` list
  and migrate in #24–#26; the list must only shrink.

## Consequences

- One versioned source of truth for interface icons; icon updates are a
  `scripts/sync-lucide-icons.sh` run, not a symbol-name hunt.
- Syncs stay small and reviewable: only the epic-table SVGs are vendored.
- Lucide is outline-only (no `.fill` variants); semantic color keeps coming
  from `WorkbenchPalette`, `.accentColor`, and surrounding context.
