---
name: swift-conventions
description: Swift coding conventions for GitMenuBar covering naming, previews, type-safety, and lint-friendly structure.
---

# Swift Conventions

Use this skill when editing Swift files in the app or test targets.

## Rules

- Prefer descriptive names and small focused types or functions.
- Use early returns to keep control flow shallow.
- Avoid force unwraps unless failure is truly impossible and localized.
- Keep files and declarations within lint size limits; split before they become hard to review.
- UI-rendering Swift files must include at least one `#Preview`.

## Repository Conventions

- Feature-specific UI stays near the owning feature; shared UI should move to the shared layer once reuse is real.
- Infrastructure code should not drift into view files.
- Keep naming explicit enough that AI-assisted edits can target the right file without guesswork.

## Tooling

- `make lint`
- `make lint-fix`
