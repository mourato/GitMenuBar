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
