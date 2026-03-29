---
name: code-quality
description: Refactoring and maintainability guidance for GitMenuBar with emphasis on deduplication, dead-code removal, and architectural clarity.
---

# Code Quality

Use this skill when simplifying code, moving responsibilities, or cleaning up unused pieces exposed by a change.

## Checklist

- Reuse an existing helper before adding another abstraction.
- Keep side effects localized and named clearly.
- Prefer one obvious owner for each workflow over thin wrappers that only forward calls.
- Remove dead UI, dead helpers, dead resources, and stale previews in the same change when they become unused.
- Support every removal with objective evidence: search results, target wiring, preview/runtime path, or call-site analysis.

## Refactor Strategy

- Prefer behavior-preserving refactors in small slices.
- Separate broad moves from behavior changes when practical.
- If a file is large because it mixes concerns, split by ownership boundary rather than by arbitrary line count.

## Validation

- `make build`
- `make test`
- Run `make lint` when the refactor changes structure enough to affect style or size rules.
