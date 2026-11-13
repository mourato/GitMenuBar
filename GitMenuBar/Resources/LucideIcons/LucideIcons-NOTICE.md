# Lucide Icon Notices

GitMenuBar vendors a pinned subset of SVG files from `lucide-static`.

- Package: `lucide-static@1.72.0`
- Source: `https://unpkg.com/lucide-static@1.72.0/icons/<name>.svg`
  (npm registry tarball `lucide-static-1.72.0.tgz`)
- License: ISC (`Copyright (c) 2026 Lucide Icons and Contributors`)
- Upstream: <https://github.com/lucide-icons/lucide>

Files are byte-identical to upstream, including the per-file
`<!-- @license lucide-static vX.Y.Z - ISC -->` comment.

See `docs/lucide-icons.md` for the catalog policy and
`scripts/sync-lucide-icons.sh` for the vendored subset. The file is named
`LucideIcons-NOTICE.md` (not `NOTICE.md`) because Xcode flattens synchronized
resource folders and `FileTypeIcons/NOTICE.md` already claims that name.
