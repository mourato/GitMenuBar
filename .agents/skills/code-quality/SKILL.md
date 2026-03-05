---
name: code-quality
description: Refactoring and maintainability standards.
---

# Code Quality

## Checklist
- Reuse existing helpers before creating new ones.
- Keep side effects localized and explicit.
- Reduce duplication across menu views and managers.
- Prefer behavior-preserving refactors in small commits.

## Verification
- Run `make build` and `make test` after refactors.
