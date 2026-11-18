---
name: security-credentials
description: GitMenuBar credential handling — Keychain storage, GitHub tokens, AI provider keys, migrations, and sensitive logging.
---

# Security Credentials

## When to use

Touching GitHub auth, AI provider keys, secret persistence, migrations, or error and logging paths that could expose sensitive data.

## Project specifics

- Secrets live in Keychain under `GitMenuBar/Services/Credentials/` (`AIKeychainStore`, `KeychainItemClient`), never UserDefaults or plaintext files.
- Provider configuration and the selected default provider are non-secret metadata; API keys and GitHub tokens stay secret at every layer.
- Migrations are idempotent and safe to rerun: they preserve access while cleaning up legacy locations.
- Never log tokens, API keys, authorization headers, or raw secret payloads. User-facing errors explain the action needed without exposing the value or transport details.
- Deletes and overwrites leave no stale in-memory mirror beyond the owning cache. Tests cover save, load, delete, migration, and cache invalidation (`GitMenuBarTests/AIKeychainStoreTests.swift`).

## Follows global security-best-practices

Global `security-best-practices` ships guidance for Python, JavaScript/TypeScript, and Go only, so it has no Swift or Keychain material — this file keeps the Swift parts. Project-level facts stay in `AGENTS.md`.
