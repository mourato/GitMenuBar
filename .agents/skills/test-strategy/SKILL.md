---
name: test-strategy
description: Test design guidance for GitMenuBar with emphasis on XCTest coverage, async behavior, seams, doubles, and regression-focused verification.
---

# Test Strategy

Use this skill when adding behavior, refactoring logic, or deciding how to verify edge cases beyond the default build gate.

## Testing Priorities

- Prefer unit coverage for parsing, state derivation, command resolution, and action coordination.
- Test behavior around Git failures, empty states, pagination, and cancellation.
- Add regression tests for bugs that were user-visible or easy to reintroduce.
- Keep UI previews and test fixtures separate; previews are not verification.

## Design Rules

- Inject seams around Git, networking, time, and persistence.
- Favor deterministic fakes over broad mocks.
- Async tests should cover success, failure, and cancellation when concurrency is involved.
- Assert observable outcomes, not internal implementation details.

## Scope Matrix

- Pure transformation logic: unit tests expected.
- Coordinator/action logic: unit tests strongly preferred.
- Lifecycle-sensitive menu/window behavior: manual verification plus targeted tests where seams exist.
- Packaging and release flow: manual verification through `release-management`.

## Path-switch concurrency regression

For a Git action that may finish after project selection changes, follow
[`ADR 0009`](../../docs/adr/0009-path-bound-git-operations.md):

- use two distinct canonical repository paths, A and B;
- block A's operation with `CheckedContinuation`, not a sleep;
- switch through the same selection/reset transaction used by the app;
- assert the command context, push path, completion callback, and visible
  status all remain correct; and
- keep a negative case proving an unbound or atomic flow still blocks B.

Prefer observable outcomes over fake-manager state. A test that only mutates a
double's selected path does not prove that the production selection transaction
clears stale UI state.
