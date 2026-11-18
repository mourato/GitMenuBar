---
name: release-management
description: Release readiness for GitMenuBar — build-release, DMG validation, and final packaging review.
---

# Release Management

## When to use

A task affects shipping readiness, packaging, or release execution.

## Project specifics

- Flow: `make build-release` (Release build via `scripts/run-build.sh`) → `make dmg` (`scripts/create-dmg.sh`) → confirm `dist/GitMenuBar.dmg` exists and mounts cleanly.
- Readiness: `make build`, `make test`, `make lint`, `make build-release`, `make dmg`.
- Packaging script changed: inspect `scripts/create-dmg.sh`, `scripts/run-build.sh`, `scripts/config/app_identity.sh`.
- App identity changed: keep bundle name, app name, and artifact paths aligned; validate the Release build, not only Debug.
- Mount the DMG and confirm the app bundle plus the `/Applications` alias; launch the packaged app once and check that the status item, main window/popover, settings, and repository selection still open.
- Record any missing signing, notarization, or changelog work explicitly; do not assume it is out of scope. `make setup-self-signed-cert` covers local signing.

## Related

- Slow startup or menu open → `performance-profiling`
- Project command surface → `docs/agents/project-workflow.md`
