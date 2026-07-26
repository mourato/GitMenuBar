# GitMenuBar interface system

Locked design decisions for product UI. Agents and humans must read this before
changing visual chrome, controls, spacing, or depth. Platform rules still come
from Apple HIG plus `.agents/overlays/apple-design.md` and
`.agents/overlays/menubar.md`. Motion defaults live in
`.agents/overlays/references/gitmenubar-motion.md` and `WorkbenchMotion`
(formerly `MacChromeMotion`).

Related ADRs:

- `docs/adr/0001-workbench-depth-and-token-naming.md`
- `docs/adr/0002-window-shell-material-and-titlebar-chrome.md`

---

## Intent

| | |
|---|---|
| **Who** | A developer mid-flow between editor and terminal |
| **Verb** | Stage → commit → sync / switch branch, with low ceremony |
| **Feel** | Dense macOS **workbench** — calm materials, quiet structure, semantic color only |

Not a SaaS dashboard. Not airy marketing chrome. Not multi-accent decoration.

---

## Domain → expression

- **Domain:** working tree, staged/unstaged, branch tip, ahead/behind, commit, sync, history, quotas
- **Color world:** system materials · accent for primary action · green/red diffs · orange warning · traffic-light quota
- **Signature:** branch chip with up/down capsules; section/file rows that trade meta (diffs) for actions on hover where policy allows
- **Reject:** metric-card grids · purple SaaS themes · shadow-on-every-section · one-size buttons · hover-only bulk Stage/Unstage

---

## Depth strategy (one — commit)

| Surface | Treatment |
|---|---|
| **Window shell** (main panel + Settings) | Window-level material / vibrancy behind content; solid fill when Reduce Transparency |
| Panel chrome, section rows | Soft borders / tints (`WorkbenchPalette`); avoid large nested `workbenchPanelSurface` plates on the main column (double-frost) |
| Header | No material plate — titlebar/toolbar chrome; traffic lights · project selector · Settings gear on one line |
| Floating overlays (command palette, popovers, sheets) | One elevation above parent; **shadows allowed here only**; popovers/sheets keep `workbenchPanelSurface` |
| Command palette scrim | Full window (including under titlebar), outside content `windowPadding`; material + subtle dim |
| Inputs | Slightly inset vs surrounding surface (platform field styles OK) |

Do **not** mix “card drop shadow on every block” with material panels.

Squint test: hierarchy readable; no harsh lines jumping out.

---

## Tokens (Swift)

Canonical enums (rename landed / landing in Plan 025):

| Type | Role |
|---|---|
| `WorkbenchMetrics` | Spacing, padding, radii, control sizes |
| `WorkbenchTypography` | Text roles + tracking helpers |
| `WorkbenchPalette` | Hover, selection, semantic fills/borders |
| `WorkbenchMotion` | Shared animations + reduce-motion adaptive |
| `WorkbenchMaterialWeight` + `workbenchPanelSurface` | Panel materials |

**No `MacChrome*` / `MacPanel*` names** after Plan 025. No long-lived typealiases.

### Spacing base

Base unit **8**. Prefer metrics over literals:

| Token | Value | Use |
|---|---:|---|
| `compactSpacing` | 8 | Icon gaps, tight HStacks |
| `sectionSpacing` | 12 | Within a card/popover group |
| `groupSpacing` | 20 | Between major panel zones |
| `panelPadding` | 16 | Popover / overlay inset |
| `windowPadding` | 12 | Settings / window panes |

Micro values **4** and **6** are allowed only as named metrics (e.g. `microSpacing`, `chipSpacing`) — do not sprinkle raw magic numbers in views.

### Radius scale

| Token | Value | Use |
|---|---:|---|
| `microCornerRadius` | 6 | Small chips / nested controls |
| `rowCornerRadius` | 8 | Rows, header chips |
| `cornerRadius` | 10 | Inline banners / small panels |
| `largeCornerRadius` | 14 | Main panel surfaces |
| Overlay (palette) | 16 | Command palette shell only |

Concentric rule: nested radius ≈ outer − padding.

### Text hierarchy (four levels)

Use weight + color/opacity more than size jumps:

1. **Primary** — repo name, primary values (`windowTitle` / body emphasized)
2. **Secondary** — section labels (`sectionLabel`)
3. **Tertiary** — supporting body / detail
4. **Muted** — paths, counts, meta (`caption` / `.secondary`)

Dynamic Type: keep using `WorkbenchTypography` + scaled metrics; do not hard-code pt sizes.

### Color

- Structure: neutrals + materials
- **One** interactive accent: system `Color.accentColor`
- Semantic only: diff green/red, warning orange, error red, success green, quota traffic light
- Hover fill ≈ `primary @ 6%`; selection ≈ `accent @ 14%` (via `WorkbenchPalette`)

---

## Button variants

Use real SwiftUI `Button`. Prefer a shared styled API (Plan 026) over one-off `.buttonStyle` choices.

| Variant | When | Visual |
|---|---|---|
| **Primary** | The one focal action on a surface (Commit, Create, Save, Connect) | `.borderedProminent`, large when it is the panel focal control |
| **Secondary** | Cancel, alternate confirms that are not destructive | Bordered / quiet filled; never equal visual weight to Primary on the same footer |
| **Ghost** | Low-emphasis chrome (e.g. Manage…, Atomic Commits, Dismiss, Refresh) | Borderless + `WorkbenchTypography.detail` + press feedback |
| **Icon** | Header gear; Projects-row repository options; compact icon chrome | Min visible control **28×28**; clear hover fill; press feedback |
| **Destructive** | Delete / Discard / Wipe | `role: .destructive` + red treatment; never styled as Ghost |
| **Row** | Branch list, palette rows, options rows | Plain + `hoverFill` / `selectedFill`; idle background clear (not permanently filled) |

Press feedback: scale ≈ **0.97** via shared press style; respect Reduce Motion (`WorkbenchMotion.adaptive`).

### Adoption scope

- **This wave:** main panel + popovers attached to it; window shell also covers Settings (Plans 030–033)
- **Deferred:** sheets button-kit migration, confirmation dialogs (opportunistic only; Plan 029 stub)

Confirmation dialogs keep system alert patterns; do not restyle en masse.

---

## Working-tree actions (policy)

| Control | Policy |
|---|---|
| **Stage all / Unstage all** (section header) | **Always visible** when the section shows an action; do not hide behind hover; do not swap away line-diff summary to reveal them |
| **Discard all** | Hover (or equivalent) + confirmation dialog; not always-visible |
| **Per-file Open / Discard / Stage|Unstage** | Remain **hover-revealed** icons (signature density) |
| **Hit targets** | Visible icon may stay compact; **hit area ≥ 28×28** (prefer 32) via padding/`contentShape`, not tiny 18×16 frames alone |
| **Swipe + context menu** | Keep (Plan 014); complementary, not replacements |
| **Keyboard (this wave)** | Keep ↑/↓, Return = open, Delete = discard unstaged. **No new** per-file stage shortcut |

---

## Main panel composition

Current vertical order (do not invent a new IA without a plan):

1. Header (titlebar-aligned: traffic lights · project selector · Settings gear)
2. Commit composer (Primary commit/sync)
3. Scroll: banners → staged → unstaged → history
4. Footer: branch chip · Ghost actions (Atomic / Manage)
5. Optional usage quota cards (Mimir-style; secondary to Git workflow)

### Header chrome

- Single horizontal line with native traffic lights (leading), project selector (principal / centered), and Settings gear (trailing). Visually separated across the full titlebar width; **no** header `workbenchPanelSurface` plate.
- Main body adds top `sectionSpacing` under the titlebar so the first content control is not tight against the header.
- **Commit Details** route reuses the same titlebar toolbar slots: principal title “Commit Details”, trailing Back (`chevron.backward` in the Settings slot). Do not use an in-content back/title bar on that route — missing toolbar chrome shifts traffic lights.
- Repository Options (ellipsis) lives on the **current** project row inside the Projects popover only (hidden when options unavailable or row is not current). Keep project-button context menu + status-item / command-center entry points; remove header ellipsis and the popover footer “Repository Options…” duplicate.
- Opening row options: close Projects, then present Repository Options anchored to the project-selector control (existing pending-presentation flow).

### Usage quota cards

When quotas are enabled and snapshots exist, show provider cards (Codex and/or Cursor):

- Primary: provider name, interval chip, traffic-light colored remaining `%`, progress bar matching that %, countdown with icon, locale-aware **time-only** next-cycle clock with icon (`resetAt`); reset credits trail the meta row when present.
- Secondary weekly row when weekly differs from primary (same dedupe rule as the former strip).
- Group hairline border + divider between providers with vertical padding so content does not touch the rule.
- Informational only: arrow cursor (never pointing-hand) unless a control gains a real action.
- Natural height for 1–2 providers; no status-item quota glyphs.

### Liquid Glass

Opt out app-wide via `UIDesignRequiresCompatibility` in `Info.plist` for now (see ADR 0002). Future escape hatch: borderless `NSPanel` overlay like Mimir/Codex Bar if the compatibility flag is retired.

**This wave does not** demote footer Ghost actions or redesign Commit-vs-footer focal hierarchy. Footer weight stays as today; button *variants* may still apply so Ghost is consistent.

---

## Settings Form surface (locked direction)

Visual/IA reference: Vozinha’s native grouped `Form` contract (**ideas only** — recreate with Workbench tokens; do not copy source). Window shell from Plan 032 stays authoritative.

### Intent

| | |
|---|---|
| **Who** | Same workbench developer; opens Settings briefly mid-flow |
| **Verb** | Find a preference → change it → dismiss |
| **Feel** | Native macOS grouped Form on the existing material shell — calm, dense, not a second big app |

### Chrome & delivery

- **Keep** `sindresorhus/Settings` toolbar panes for now. Form primitives must stay **chrome-agnostic** so a later sidebar/custom shell swap is cheap.
- **Staged plans:** **034** (`plans/034-settings-form-surface-and-general-canary.md`) — `SettingsFormPage` + `SettingsFormSectionHeader` + layout policy; migrate **General** as canary. **035** (`plans/035-settings-form-migrate-panes-and-ia.md`) — migrate Git / AI / Shortcuts and apply the destination map below.
- Retire custom `SettingsSection` as callers migrate (no parallel forever API).

### Destination map (035)

| Pane | Owns |
|---|---|
| **General** | Login, auto-hide, mouse-monitor, appearance, **Quit** |
| **Git** | Commit-field hide, repo path, recents, GitHub, **Wipe** (Danger zone) |
| **AI** | Providers + usage quotas (replaces thin **Quotas** pane) |
| **Shortcuts** | Keyboard shortcuts only |

### Form × shell contract

- One `.formStyle(.grouped)` `Form` per pane via `SettingsFormPage`.
- Native `Section`s; shared `SettingsFormSectionHeader` (title + optional SF Symbol).
- Exactly **one** vertical scroll owner (the Form).
- `.scrollContentBackground(.hidden)` so the window material shell shows through.
- **No** new nested `workbenchPanelSurface` plates inside Settings panes; grouping comes from native sections.
- Scalars (`Toggle`, `Picker`, `LabeledContent`) use visible native labels.
- Complex blocks (repo path, recents, GitHub auth, AI provider list): **hybrid** — live inside a `Section` as custom subviews; editors stay sheets.
- Quit / Wipe are Form `Section` rows (destructive styling for Wipe), not a separate footer chrome kit.

### Geometry

- Target min width **~520–600**; drop the forced tall `420×700` min height in favor of content-driven / shorter default.

### Out of scope until a later plan

- Settings search
- Sidebar / retiring the Settings package
- Expandable / drill-down row kit (Vozinha flatten primitives)
- Aggressive single-pane flatten beyond the destination map above

---

## Section headers

Working Tree and History headers must share the same chrome primitive (padding, hover fill from `WorkbenchPalette`, radius, chevron+title type, count meta). History does not grow Stage actions — only visual/structural parity (Plan 028).

---

## States (mandatory)

Interactive controls: default, hover, pressed, focus, disabled.  
Data regions: loading, empty, error.  
Respect Reduce Motion and Reduce Transparency (solid control backgrounds when required).

---

## Out of scope for agents unless a plan says otherwise

- Mass confirmation-dialog restyle
- Sheets full button-kit migration (Plan 029 stub)
- New per-file stage keyboard shortcut
- Marketing / landing visuals
- Status-item quota glyphs / UX option B status accents
- Repository Options for non-current recent projects (no switch-then-open)
- Settings search, Settings sidebar chrome, expandable/drill-down Settings rows (see Settings Form surface)

---

## Checks before shipping UI

1. **Squint** — hierarchy without harsh borders  
2. **Signature** — branch chip / diff language still present  
3. **Token** — no new raw spacing/radius/color that belongs in `Workbench*`  
4. **Variant** — every new button maps to a variant above  
5. **Preview** — any new `View` file includes `#Preview` (repo AGENTS.md)
