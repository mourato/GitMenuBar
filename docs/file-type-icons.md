# File Type Icons

## License conclusion

**Decision:** GitMenuBar vendors a **small curated subset of `@pierre/trees`
SVG path data** for common GitMenuBar file types, rendered natively through
AppKit/SwiftUI with adaptive light/dark tint colors.

**Reference package:** [`@pierre/trees@1.0.0-beta.4`](https://www.npmjs.com/package/@pierre/trees/v/1.0.0-beta.4)

| Attribute | Value |
|-----------|-------|
| **SPDX** | `Apache-2.0` for `@pierre/trees`; `MIT` notice retained from its bundled `NOTICE.md` |
| **Source** | npm registry tarball `@pierre/trees@1.0.0-beta.6` (includes `LICENSE.md`, `NOTICE.md`) |
| **Permissibility** | Clearly permissible for redistribution and derivative use under Apache-2.0 |

**Why a curated subset instead of the full Pierre asset set**

- GitMenuBar is a native Swift/macOS app; the implementation keeps the icons as
  local SVG templates rendered by AppKit, with no JS bridge or npm runtime.
- Increase Contrast is not specially tuned for these icons today; light/dark tints follow
  the current `FileTypeIcon` color pairs.
- Plan 042 out-of-scope items explicitly exclude NPM/JS bridges and full Pierre parity.
- The vendored subset is limited to Swift, Markdown, JSON/YAML, shell, image,
  and generic document shapes used by the app's changed-file and working-tree
  diff trees.
- Color tokens are **inspired by** T3 Code's `PierreEntryIcon.tsx` pairs
  (light/dark hex values) but mapped to SwiftUI `Color`.

**Attribution**

- T3 Code (MIT) — UX reference for Diff Tree file rows and color pairing.
- `@pierre/trees` (Apache-2.0) — subset of SVG path data vendored in
  `FileTypeIcon.swift`.
- `headless-tree/core` (MIT) — retained from the `@pierre/trees` NOTICE.

**Maintenance**

When adding a new file-type token, update `FileTypeIcon.swift` and
`FileTypeIconTests.swift`. Do not import entire third-party icon packs.
