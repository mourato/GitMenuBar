---
name: release-management
description: Release readiness checks for GitMenuBar, including build-release, DMG validation, and final packaging review.
---

# Release Management

Use this skill when a task affects shipping readiness, packaging, or release execution.

## Release Flow

1. Build release artifacts with `make build-release`.
2. Package with `make dmg`.
3. Verify `dist/GitMenuBar.dmg` exists and mounts cleanly.
4. Confirm the packaged app launches, stays menu-bar style, and exposes the expected icon and bundle name.

## Scope Checks

- Packaging script changed: inspect `scripts/create-dmg.sh`, `scripts/run-build.sh`, and `scripts/config/app_identity.sh`.
- App identity changed: verify bundle name, app name, and artifact paths stay aligned.
- Release-only behavior changed: validate the Release build, not only Debug.

## Readiness Checklist

- `make build`
- `make test`
- `make lint`
- `make build-release`
- `make dmg`

## Manual Release Review

- Mount the DMG and confirm it contains the app bundle and `/Applications` alias.
- Launch the app from the packaged artifact at least once.
- Check that status item, main window/popover, settings, and repository selection still open.
- Record any missing signing, notarization, or changelog work explicitly; do not assume it is out of scope.
