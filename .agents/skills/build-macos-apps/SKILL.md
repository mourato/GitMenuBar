---
name: build-macos-apps
description: Route bootstrap/build/release requests for GitMenuBar.
---

# Build macOS Apps (GitMenuBar)

## Commands
- `make build`
- `make build-release`
- `make test`
- `make lint`
- `make dmg`

## Routing
- New setup/bootstrap: establish Git + Make/script baseline first.
- Build failures: reproduce with `make build` and inspect `/tmp/gitmenubar-build-*.log`.
- Test failures: run `make test` and inspect `/tmp/gitmenubar-test.log`.
- Release packaging: run `make dmg` and verify `dist/GitMenuBar.dmg`.
