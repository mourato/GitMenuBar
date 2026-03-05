---
name: swift-conventions
description: Swift style and type-safety conventions for this repo.
---

# Swift Conventions

## Rules
- Prefer descriptive names and small focused functions.
- Avoid force unwraps unless strictly necessary.
- Keep types and functions below lint size limits.
- Use early returns to reduce nesting.

## Tooling
- Lint with `make lint`.
- Auto-fix with `make lint-fix`.
