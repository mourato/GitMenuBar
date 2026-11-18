---
name: test-strategy
description: Test design for GitMenuBar — XCTest priorities, seams and fakes, the scope matrix, and path-switch concurrency regressions.
---

# Test Strategy

## When to use

Adding behavior, refactoring logic, or deciding how to verify edge cases beyond the default build gate.

## Project specifics

- Prioritize parsing, state derivation, command resolution, and action coordination; cover Git failures, empty states, pagination, and cancellation. Add a regression test for each user-visible bug.
- Inject seams around Git, networking, time, and persistence. Prefer deterministic fakes over broad mocks; async tests cover success, failure, and cancellation; assert observable outcomes, not internal details.
- Scope: pure transformation logic and coordinators expect unit tests; lifecycle-sensitive menu/window behavior is manual plus targeted tests where seams exist; packaging is manual through `release-management`.
- Commands: focused `make test-focused TEST_FILTER='GitMenuBarTests/Name'`; full `make test`.
- Path-switch concurrency regression (`docs/adr/0009-path-bound-git-operations.md`): use two distinct canonical repository paths, block A's operation with `CheckedContinuation` rather than a sleep, switch through the same selection/reset transaction the app uses, and assert command context, push path, completion callback, and visible status. Keep a negative case proving an unbound or atomic flow still blocks B. A test that only mutates a double's selected path proves nothing.

## Follows global test-hygiene

`test-hygiene` owns test value, independent oracles, isolation, cleanup, and evidence. Related: `performance-profiling` for latency-sensitive Git work, `release-management` for packaging gates.
