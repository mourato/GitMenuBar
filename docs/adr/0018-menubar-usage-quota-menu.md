# ADR 0018: Native menu-bar quota menu

Status: Accepted
Date: 2026-09-13

## Context

GitMenuBar already fetches and caches provider quota snapshots, but exposed
them only in the main window's project sidebar. Bloom demonstrates a compact
native status-item workflow: the status item carries selected figures and its
menu hosts provider cards while ordinary menu rows retain app actions.

The previous quota plans deliberately excluded the status item. The product
now requires that quota workflow and the existing Git command workflow to
coexist without adding a second status item owner or a new credential path.

## Decision

- Keep `StatusBarController` as the sole `NSStatusItem` owner.
- Show quota figures in the existing status item only when the quota preference
  is enabled and its visibility is `Always`. `Menu only` keeps the quota menu
  available while hiding the figures from the status item.
- Use left click for the native quota menu, with an explicit Open GitMenuBar
  action. Preserve right click and Control-click for the existing Git command
  menu.
- Reuse `UsageQuotaStore`, its snapshot cache, provider toggles, and existing
  provider icons. Persist only presentation choices: provider order, up to two
  selected metrics per provider, text/bars, left/used, and status-item
  visibility.
- Keep custom rendering limited to the quota block inside the native menu and
  the compact status-item image. Render the strip as a template when possible;
  when the attention badge requires a multicolor image, resolve AppKit's
  semantic label color against the status item's effective appearance. All
  other actions remain ordinary `NSMenuItem` rows.

## Consequences

The quota feature has one data source and two views: the existing sidebar
cards and the status-item workflow. Status-item clicks no longer open the main
window directly while quota figures are enabled, so the menu includes a direct
main-window action. The status item remains readable in light and dark menu
bars, including when the Git attention badge is present. No provider
credentials or tokens are duplicated.

Claude Code contributes local rate-limit events when available; it remains
unavailable for accounts that do not expose such events.

## Rejected or deferred

- A second status item or independent quota store.
- OAuth or credential scraping for Claude Code.
- A fully generic provider-metric schema before a provider requires it; the
  current snapshot windows and credit field are enough for the supported set.
