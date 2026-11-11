# ADR 0023: Issue label edits use labelable mutations

Status: Accepted
Date: 2026-11-11

## Context

The Issues side panel lists repository issues and their labels. Applying or
removing one label must reach only the chosen issue and label, keep the
issue's other labels, including concurrent changes, and keep the list
readable when the signed-in account cannot write. GitHub offers both a full
label-set update on the issue and record-level add/remove mutations on a
labelable.

## Decision

- Add and remove use `addLabelsToLabelable` and
  `removeLabelsFromLabelable` with the issue's GraphQL node ID and one label
  node ID. Never send `updateIssue` with a computed label array.
- The mutation reply returns the issue's labels as GitHub confirms them. The
  list replaces its local label set only with that reply.
- Repository labels and `viewerPermission` come from one query. READ keeps
  the list and hides label actions behind an explanation; ADMIN, MAINTAIN,
  WRITE, and TRIAGE allow edits.
- A GraphQL FORBIDDEN or INSUFFICIENT_SCOPES error, or an HTTP 403, switches
  the panel to read-only with the same explanation.
- One label change runs at a time. The affected row shows progress, and every
  label menu stays disabled until the change completes or fails.
- Creating, renaming, or deleting repository labels stays out of scope.

## Consequences

- Concurrent label changes on the same issue survive, because no request
  sends a complete label set.
- A change never shows as done before GitHub confirms it. A failed reply
  keeps the previous labels and offers a retry.
- A permission problem can show before the first write when
  `viewerPermission` is READ, and after one when the token lacks a scope or
  the grant was revoked.
- Removing a label from an issue never deletes the label from the repository;
  the two operations have distinct endpoints and copy.
