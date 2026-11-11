# ADR 0024: Repository labels are created from the issue label picker

Status: Accepted
Date: 2026-11-11
Related: [ADR 0023](0023-issue-label-mutations.md) (issue label edits)

## Context

The Issues side panel can apply and remove labels that already exist in the
repository, but a missing category still sends the user to the browser in the
middle of triage. Creating a label is a repository write, not an issue write,
and #12 established that issue label changes name only the chosen issue and
label. The create action must not blur the line between the two.

## Decision

- The per-issue tag menu ends with `New Label in Repository`, which opens a
  sheet. The sheet names the repository and states that the new label becomes
  available to every issue there and is not applied to the issue that opened
  the menu.
- The sheet collects a name, a color from the native color picker, and an
  optional description. The name is trimmed and limited to 50 characters, the
  description to 100, and the color is sent as six lowercase hexadecimal digits
  without `#`.
- The labels query that already returns `viewerPermission` also returns the
  repository node ID. Creation uses the GraphQL `createLabel` mutation with
  that ID, so the token still reaches only `api.github.com` and one query
  answers both permission and target.
- Required fields, an invalid color, and a name that matches a label already in
  the picker (compared without case) stop before any request. GitHub's
  already-taken and invalid-details replies map to their own messages. A
  FORBIDDEN, INSUFFICIENT_SCOPES, or HTTP 403 reply keeps the panel read-only.
- Only the confirmed `createLabel` reply adds the label to the picker.
  Creating a label never applies it to an issue; applying remains the existing
  toggle action, so creating and applying are two explicit effects.
- Cancel and sheet dismissal send no request and change nothing. A failed
  creation leaves the picker unchanged and keeps the sheet open with a message.
- Accounts that cannot write never see the create action.

## Consequences

- Triage no longer leaves the app to add a missing category.
- The picker can briefly be stale when another account creates a label at the
  same time; GitHub's already-taken reply explains it, and Refresh Issues
  reloads the list.
- Renaming, recoloring, and deleting labels stay out of scope, as does managing
  labels across repositories at once.
