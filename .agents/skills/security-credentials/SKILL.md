---
name: security-credentials
description: Security review guidance for GitMenuBar credentials, including Keychain, token handling, migrations, and sensitive logging.
---

# Security Credentials

Use this skill when touching GitHub auth, AI provider keys, persistence of secrets, migrations, or error/logging paths that might expose sensitive data.

## Core Rules

- Store secrets in Keychain, not UserDefaults or plaintext files.
- Never log tokens, API keys, authorization headers, or raw secret payloads.
- Migrations must be idempotent and safe to rerun.
- Error messages shown to users should explain the action needed without exposing the secret value or transport details.
- Deletes and overwrites of credentials should leave no stale in-memory mirrors beyond the owning cache.

## Review Checklist

- Where does the credential enter memory?
- Where is it persisted, cached, rotated, or deleted?
- Can debug prints or thrown errors leak values?
- Does migration preserve access while cleaning up legacy locations?
- Are tests covering save, load, delete, migration, and cache invalidation paths?

## GitMenuBar Focus

- Review `Services/Credentials/` and AI provider settings together; they are one security surface.
- Treat provider configuration and selected default provider as non-secret metadata, but keep API keys and GitHub tokens secret at every layer.
