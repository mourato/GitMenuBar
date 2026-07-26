# GitMenuBar

Native macOS menu-bar Git client. This glossary records product language for
GitMenuBar surfaces; keep it free of implementation detail.

## Language

### Changed files

**Changed Files Summary**:
The collapsible overview of files touched by a commit or by the current
working tree, with aggregate insertions/deletions and a hierarchical path tree.
_Avoid_: card (for this surface — it uses Workbench section chrome, not a
chat-style bordered card), turn diff, checkpoint files

**Diff Tree**:
The hierarchical folder/file listing inside a Changed Files Summary, including
aggregated per-folder stats and optional single-child path compaction.
_Avoid_: file list (when the hierarchical tree is meant), outline view

**Path Compaction**:
Merging a chain of single-child directories into one path label
(e.g. `GitMenuBar/Pages/MainMenu`).
_Avoid_: flatten, collapse path (ambiguous with UI collapse)

**Compact Preview**:
The collapsed Changed Files Summary state that shows top-level scope labels and
a small set of file chips before the full Diff Tree is revealed.
_Avoid_: teaser, snippet row

**Open Diff**:
The primary navigation action from a Changed Files Summary into the external
diff destination (GitHub commit or file-at-commit URL when available; otherwise
the on-disk file).
_Avoid_: show diff (implies an in-app diff viewer we do not ship yet)

### Working tree

**Staged** / **Unstaged**:
The two working-tree buckets GitMenuBar keeps separate; each may host its own
Diff Tree without merging into a single unified changed-files list.
_Avoid_: index / workdir as user-facing labels

**Working Tree Status Letter**:
The trailing `M` / `D` / `U` mark on a working-tree file row.
_Avoid_: badge (unless referring to the status-item glyph)

### Icons

**File Type Icon**:
The glyph beside a file name in a Diff Tree. Phase 1 uses SF Symbols by
extension/name; a later phase may add colored language icons.
_Avoid_: Pierre icon (reference-only name unless documenting the T3Code source)
