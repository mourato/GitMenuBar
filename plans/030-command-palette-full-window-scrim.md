# Plan 030: Make command palette scrim cover the full window

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 7ade5a9..HEAD -- GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift GitMenuBar/Pages/MainMenu/MainMenuContent.swift .interface-design/system.md plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `7ade5a9`, 2026-07-25

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: `no` — shares MainMenu overlay host with later chrome plans
- **Reviewer required**: `no`
- **Rationale**: Localized SwiftUI overlay attachment + scrim styling; no AppKit window surgery.
- **Escalate when**: fix requires changing `NSWindow` / titlebar embedding, or palette modal layout redesign beyond scrim.

## Why this matters

When ⌘K opens the command palette, the dimming scrim is clipped to the padded content box, leaving visible gutters on left/right/bottom. An overlay must cover the **entire window** (including under the transparent titlebar). Fixing attachment order also unblocks Plans 031–032 so later chrome work is not judged against a broken scrim.

## Current state

`MainMenuView` applies horizontal + bottom `windowPadding` (20pt) on the root view. The palette overlay is applied via `applyMainViewOverlays` on `mainView` **inside** that padded tree, so the scrim inherits the inset.

```270:271:GitMenuBar/Pages/MainMenu/MainMenuView.swift
        .padding(.horizontal, WorkbenchMetrics.windowPadding)
        .padding(.bottom, WorkbenchMetrics.windowPadding)
```

```34:58:GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift
    private func applyCommandPaletteOverlay<Content: View>(to view: Content) -> some View {
        view.overlay {
            if isCommandPalettePresented && presentationModel.route == .main {
                ZStack {
                    commandPaletteScrim
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeCommandPalette()
                        }
                        // ...
                    MainMenuCommandPaletteView(...)
                }
            }
        }
    }
```

Scrim today is `.ultraThinMaterial` (or solid when Reduce Transparency) — no extra dim:

```61:68:GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift
    private var commandPaletteScrim: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
```

Design contract (locked): full-window scrim outside content padding; material + subtle dim. See `.interface-design/system.md` → Depth strategy → Command palette scrim. ADR: `docs/adr/0002-window-shell-material-and-titlebar-chrome.md`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift | `git diff --stat 7ade5a9..HEAD -- GitMenuBar/Pages/MainMenu/MainMenuView.swift GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` | understood |
| Incremental | `make agent-check` | exit 0 |
| Full gate | `make lint && make test` | exit 0 |
| Scrim inset check | `rg -n 'windowPadding|applyMainViewOverlays|commandPaletteScrim' GitMenuBar/Pages/MainMenu/` | padding not wrapping overlay host |

## Suggested executor toolkit

- `apple-design`, `macos-app-engineering`, `swift-conventions`
- Keep Reduce Transparency / Reduce Motion paths intact

## Scope

**In scope**

- `GitMenuBar/Pages/MainMenu/MainMenuView.swift` — restructure so content keeps `windowPadding`, but command-palette overlay attaches to a full-window host (edge-to-edge, including under titlebar / safe areas as needed)
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` — scrim = material + subtle dim (e.g. ultraThinMaterial over a low-opacity black/primary fill, or equivalent); tap-outside still dismisses; traffic lights remain usable
- Previews if overlay preview harness needs updating (`MainMenuCommandPalettePreview.swift` only if required for compile)

**Out of scope**

- Header / titlebar alignment (Plan 031)
- Window-level material shell (Plan 032)
- Quota UI (Plan 033)
- Changing palette item content, search behavior, or modal width
- Settings window

## Git workflow

- Branch: `feat/030-command-palette-full-scrim`
- Commit example: `fix(ui): stretch command palette scrim to full window`
- Do NOT push or open a PR unless asked

## Steps

### Step 1: Relocate overlay host outside content padding

Restructure `MainMenuView` / `mainView` so:

1. Inner content (header, commit, scroll, footer, quotas) still uses `WorkbenchMetrics.windowPadding` horizontally and bottom.
2. `applyMainViewOverlays` (or an equivalent full-bleed `.overlay`) is applied on a container that is **not** inset by that padding.
3. Scrim uses `.ignoresSafeArea()` (and titlebar-safe extension as needed) so left/right/bottom gutters disappear and coverage includes the titlebar region.

Prefer the smallest structural change (e.g. apply padding to the inner `VStack` only, overlays on the outer frame) over a rewrite of route switching.

**Verify**: `make agent-check` → exit 0

### Step 2: Enrich scrim (material + subtle dim)

Update `commandPaletteScrim` to stack material with a subtle dim while preserving Reduce Transparency solid fallback. Keep tap-to-dismiss on the scrim. Do not block traffic-light hit testing if AppKit still owns those controls (scrim is content-view overlay; STOP if you find you must swallow titlebar mouse events to “cover” the window — report instead of fighting the window chrome).

**Verify**: `rg -n 'commandPaletteScrim|ultraThinMaterial|black\.opacity|primary\.opacity' GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift` → shows material + dim (or documented equivalent), plus Reduce Transparency branch

### Step 3: Manual visual check list (document in PR / commit body)

- Open palette: no padded gutters L/R/bottom
- Scrim reaches titlebar area; modal remains centered and usable
- Tap scrim dismisses; Escape still closes
- Reduce Transparency: solid scrim, still full-bleed

**Verify**: `make lint && make test` → exit 0

## Test plan

- No new unit tests required unless you extract a pure layout helper (unlikely).
- Rely on existing command-palette resolver tests still passing.
- If a UI test harness exists for MainMenu overlays, extend only if cheap; otherwise manual checklist above is enough for this S plan.

## Done criteria

- [ ] Palette scrim is not clipped by `windowPadding` (structural: overlay outside padded content)
- [ ] Scrim uses material + subtle dim with Reduce Transparency fallback
- [ ] `make agent-check` exit 0
- [ ] `make lint && make test` exit 0
- [ ] No files outside Scope modified (`git status`)
- [ ] `plans/README.md` status row for 030 updated

## STOP conditions

- Overlay cannot cover under titlebar without breaking traffic lights or auto-hide — stop and report (Plan 031/032 may need to own titlebar interaction).
- Fix appears to require rewriting `StatusBarController` window creation.
- Drift in Current state excerpts.

## Maintenance notes

- Reviewers: confirm padding still insets **content**, not the scrim.
- Plan 032’s window material will show through this scrim — keep dim subtle.
- Do not re-introduce overlay inside padded `VStack`.
