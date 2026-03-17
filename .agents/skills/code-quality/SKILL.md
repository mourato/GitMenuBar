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
- When code/UI/resources become unused, remove them in the same change with explicit evidence of non-usage.
- Do not keep legacy files "just in case"; if rollback safety is needed, rely on version control instead of dead code.

## Verification
- Run `make build` and `make test` after refactors.
