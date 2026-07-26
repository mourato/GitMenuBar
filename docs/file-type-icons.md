# File Type Icons

## License conclusion

**Decision:** GitMenuBar uses **native SF Symbols with adaptive light/dark tint colors**.
We do **not** vendor SVG or path data from `@pierre/trees` or T3 Code.

**Reference package:** [`@pierre/trees@1.0.0-beta.4`](https://www.npmjs.com/package/@pierre/trees/v/1.0.0-beta.4)

| Attribute | Value |
|-----------|-------|
| **SPDX** | `Apache-2.0` |
| **Source** | npm registry tarball (includes `LICENSE.md`, `NOTICE.md`) |
| **Permissibility** | Clearly permissible for redistribution and derivative use under Apache-2.0 |

**Why SF Symbols instead of vendoring Pierre assets**

- GitMenuBar is a native Swift/macOS app; SF Symbols integrate with system appearance
  and Dynamic Type without sprite conversion or JS bridges.
- Increase Contrast is not specially tuned for these icons today; light/dark tints follow
  the current `FileTypeIcon` color pairs.
- Plan 042 out-of-scope items explicitly exclude NPM/JS bridges and full Pierre parity.
- Color tokens are **inspired by** T3 Code's `PierreEntryIcon.tsx` pairs (light/dark hex
  values) but mapped to SwiftUI `Color` — no Pierre icon path data is copied.

**Attribution**

- T3 Code (MIT) — UX reference for Diff Tree file rows and color pairing.
- `@pierre/trees` (Apache-2.0) — license verified; not bundled in this app.

**Maintenance**

When adding a new file-type token, update `FileTypeIcon.swift` and
`FileTypeIconTests.swift`. Do not import entire third-party icon packs.
