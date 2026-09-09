# Plan 054: Consolidar credenciais de providers AI em um item seguro do Keychain

> **Executor instructions**: Execute este plano na ordem. O escopo envolve
> persistência, migração e segurança; não altere o comportamento de tokens
> locais do Codex/Cursor nem do token do GitHub. Nunca imprima, registre ou
> coloque valores de chaves em testes, logs, planos ou mensagens. Se uma
> condição de parada ocorrer, pare e reporte em vez de improvisar.
>
> **Drift check (run first)**: `git diff --stat 75341b1..HEAD -- GitMenuBar/Models/AIModels.swift GitMenuBar/Services/AI GitMenuBar/Services/Credentials GitMenuBar/Services/UsageQuota GitMenuBar/App/StatusBarController.swift GitMenuBarTests CONTEXT.md docs/adr plans/054-consolidate-ai-provider-credentials.md`

## Status

- **Priority**: P0
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: security, migration, tech-debt, tests
- **Planned at**: commit `75341b1`, 2026-08-05

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no — the credential identity, blob schema, migration, cache and quota/commit consumers must agree on uma única fronteira.
- **Reviewer required**: yes — persistence de credenciais, migração de Keychain, concorrência e disponibilidade enquanto o Mac está bloqueado.
- **Rationale**: A mudança precisa preservar instalações existentes, compartilhar OpenRouter/Google entre domínios e evitar perda silenciosa em falhas de `SecItem`. Um executor rápido não deve escolher política de conflito ou inventar fallback.
- **Escalate when**: a migração precisar tocar o token do GitHub, tokens locais Codex/Cursor, bundle/access group, um segundo item de Keychain, ou uma resolução automática de conflito entre duas chaves diferentes.

## Why this matters

Hoje o commit generation grava uma chave por UUID de provider e o OpenRouter quota usa um item separado. Assim, duas configurações do mesmo backend podem divergir e o usuário pode ser solicitado várias vezes pelo Keychain após um build. O resultado deve ser um único item versionado para as chaves de API AI, com identidade por backend, cache seguro e migração que só remove origens depois de validar o destino.

## Current state

- `GitMenuBar/Services/Credentials/AIKeychainStore.swift:4-8,18-37,63-112` define `AIAPIKeyStore`, grava `provider-<UUID>` como itens independentes e faz `delete` antes de `SecItemAdd`; `:139-234` implementa um cache separado que pré-carrega por UUID.
- `GitMenuBar/Services/UsageQuota/OpenRouterAPIKeyStore.swift:4-65` mantém outro item fixo (`openrouter-api-key`) para a mesma classe de credencial.
- `GitMenuBar/Services/AI/AICommitCoordinator.swift:119-140,171-197` resolve credenciais por `provider.id`; `GitMenuBar/Services/AI/GitMenuBarCommitSession.swift:47-50,198-225` usa o mesmo contrato para o Companion CLI.
- `GitMenuBar/App/StatusBarController.swift:65-107` cria o store AI cacheado e o pré-carrega; `UsageQuotaStore.swift:58-65` cria `OpenRouterUsageProvider()` com seu próprio store.
- `GitMenuBar/Services/Credentials/KeychainMigrator.swift:9-55,75-149` migra UserDefaults, GitHub e AI, mas ignora status de `SecItemAdd/Delete`, apaga a origem cedo e marca a migração concluída sem verificação.
- `GitMenuBar/Models/AIModels.swift:3-32` possui `.openAI`, `.anthropic` e `.gemini`, mas não possui `.openRouter`; providers OpenRouter existentes são identificados na prática por endpoint/configuração OpenAI-compatible.
- A referência confirmada da `vozinha` é `/Users/usuario/Documents/Projects/vozinha/Packages/MeetingAssistantCore/Sources/Infrastructure/Services/KeychainManager.swift:183-291,331-429`: payload `Codable` versionado em um blob, cache protegido por lock, `SecItemUpdate` com fallback para add e migração antes da limpeza.
- O glossário atual define **AI usage quotas** como uma superfície distinta de AI Commit Generation e **Credit Balance** como a medição OpenRouter. Compartilhar a credencial não deve fundir esses domínios.
- Plan 047 registrou a antiga decisão de manter OpenRouter fora de `AIProviderStore`; essa decisão está superseded pela confirmação do usuário neste plano. Não reintroduza a separação de credenciais.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Targeted credentials tests | `xcodebuild -project GitMenuBar.xcodeproj -scheme GitMenuBar -destination 'platform=macOS' -only-testing:GitMenuBarTests/AIKeychainStoreTests -only-testing:GitMenuBarTests/CredentialStoreCacheTests -only-testing:GitMenuBarTests/AICommitCoordinatorTests test` | exit 0; targeted tests pass |
| Full tests | `make test` | exit 0; XCTest suite passes |
| Lint | `make lint` | exit 0; no new violations in touched files |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Diff hygiene | `git diff --check` | exit 0; no whitespace errors |

The current baseline also has `make check-preview` failing on a clean tree with
`files[@]: unbound variable` in `scripts/check-preview.sh`; this UI-independent
baseline is not a reason to change the script in this plan.

## Scope

**In scope** (the only production/test/docs files this plan may modify):

- `GitMenuBar/Models/AIModels.swift`
- `GitMenuBar/Services/Credentials/AIKeychainStore.swift`
- `GitMenuBar/Services/Credentials/KeychainMigrator.swift`
- `GitMenuBar/Services/UsageQuota/OpenRouterAPIKeyStore.swift` (remove after all callers migrate)
- `GitMenuBar/Services/UsageQuota/OpenRouterUsageProvider.swift`
- `GitMenuBar/Services/UsageQuota/UsageQuotaStore.swift`
- `GitMenuBar/Services/AI/AICommitCoordinator.swift`
- `GitMenuBar/Services/AI/GitMenuBarCommitSession.swift`
- `GitMenuBar/App/StatusBarController.swift`
- `GitMenuBar/Services/Persistence/AppPreferences.swift`
- targeted files under `GitMenuBarTests/`
- `CONTEXT.md`
- one new ADR under `docs/adr/` if the decision remains hard to reverse and surprising after implementation

**Out of scope**:

- `GitMenuBar/Services/Credentials/GitHubTokenStore.swift` storage shape or accessibility policy
- Codex/Cursor token readers, their local auth files/SQLite, and snapshot persistence
- adding a Gemini/Google quota provider
- UI ordering and provider-management sheet; Plan 055 owns that surface
- Wipe removal; Plan 056 owns that independent deletion
- new dependencies, database storage, environment-variable fallback, or a second consolidated item

## Credential identity contract

Implement one small, Codable identity value used by commit generation and
Usage Quotas. Its stable serialized keys must be:

- `openrouter` when the provider endpoint host is `openrouter.ai` or a documented OpenRouter subdomain;
- `google` when the provider is `.gemini` and uses the built-in Google Generative Language endpoint;
- `openai` and `anthropic` for their built-in endpoints/types;
- `custom:<provider UUID in lowercase>` for any non-built-in endpoint or custom-compatible provider.

Do not key the new blob by display name. Preserve existing provider UUIDs in
UserDefaults; only the credential lookup identity changes. If two existing
legacy items resolve to one identity with different values, retain all legacy
items, mark a pending conflict without logging values, and do not select one
silently. Equal values may coalesce.

## Steps

### Step 1: Add the shared backend identity and map existing providers

In `AIModels.swift`, add the smallest `AIProviderCredentialID` value type needed
to represent the four built-in identities and `custom:<UUID>`. Add one resolver
from `AIProviderConfig` that normalizes the endpoint URL host before deciding
whether it is built-in or custom. The resolver must classify the existing
OpenRouter-as-OpenAI configurations by host, not by display name.

Update `AIProviderConfig`/decoding only if needed for backward-compatible
serialization; do not rewrite existing provider IDs or persisted provider
payloads. Add unit tests for built-in endpoints, OpenRouter-compatible
endpoints, custom endpoints, case/port normalization, and malformed URLs.

**Verify**: `xcodebuild -project GitMenuBar.xcodeproj -scheme GitMenuBar -destination 'platform=macOS' -only-testing:GitMenuBarTests/AIProviderStoreTests test` → exit 0 and the new identity cases pass.

### Step 2: Replace independent Keychain items with one versioned AI blob

Refactor `AIKeychainStore` so its public contract reads/writes by
`AIProviderCredentialID`, while keeping an in-memory fake for tests. Store a
single `Codable` payload such as `{ version, values: [serializedIdentity: key] }`
under one stable account in service `com.mourato.GitMenuBar`.

Make persistence failures observable: the production protocol and its test
fake must use `throws` (or an equivalently explicit `Result`, consistently at
every caller), and `AICommitCoordinator.saveAPIKey` must propagate that result
to the editor instead of swallowing it. Plan 055 consumes this error-aware
contract; it must not guess whether a failed write succeeded.

Match the confirmed `vozinha` approach, with these GitMenuBar constraints:

- use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for the new AI blob;
- protect cache and read-modify-write with one lock boundary;
- use `SecItemUpdate` and add-on-not-found, never delete-before-add;
- treat `errSecItemNotFound` as an empty store, but distinguish
  `errSecInteractionNotAllowed`/other failures from a missing key;
- never log payloads, key values, serialized blobs, or HTTP credentials;
- do not store the GitHub token or local Codex/Cursor session tokens in this blob.

Keep the cache API used by `StatusBarController`, but make preload/read/write
operations use the same identity and serialized backing store. The backing
store must not allow a stale preload to overwrite a later save/delete.

**Verify**: targeted credentials tests → exit 0; a test double proves update,
add-on-missing, missing-item, locked-item and write-failure paths without
printing a secret value.

### Step 3: Make migration versioned, validated and retryable

Extend or replace the AI portion of `KeychainMigrator` with an independent
version marker; do not let the already-existing
`hasMigratedKeychainDomain` boolean skip this new migration on upgraded
installations.

Migration order:

1. Read current-service and legacy-service AI items by provider UUID, plus the
   fixed OpenRouter item.
2. Resolve each provider UUID through the persisted `AIProviderConfig` list;
   preserve an unmappable legacy entry and report it as a migration issue,
   never discard it.
3. Coalesce equal values into the consolidated payload. If one identity has
   conflicting values, omit that ambiguous identity from the destination,
   leave every conflicting legacy item intact, and keep the migration marker
   pending; the implementation must not choose one silently.
4. Write the complete unambiguous blob, reread and decode it, and verify every
   migrated identity/value written to the destination is present without
   exposing the value.
5. Only after verification, delete the corresponding legacy AI items and
   advance the version marker. A partial failure or unresolved conflict must
   leave origins intact and be safe to retry on the next launch.

Harden the existing migration status handling so a failed `SecItemAdd` or
`SecItemDelete` cannot be treated as success. Preserve the existing GitHub and
UserDefaults migration scope and service identifiers; do not move GitHub into
the AI blob.

**Verify**: migration tests → exit 0 with cases for empty legacy state, one
UUID provider, fixed OpenRouter provider, equal duplicate values, conflicting
values, malformed blob, destination write failure, destination read-back
failure, retry after partial failure, and already-migrated installation.

### Step 4: Route commit generation, CLI and OpenRouter quota through the shared store

Update `AICommitCoordinator`, `GitMenuBarCommitSession`, and the cached store
callers to resolve `AIProviderCredentialID` from the full provider config. Keep
the `throws`/explicit-result behavior from Step 2 through coordinator and UI
boundaries so a Keychain failure cannot be mistaken for a successful save.
`hasStoredAPIKey` remains only a non-secret UI presence flag and must be
updated after a successful write/read, not before.

Replace `OpenRouterAPIKeyStoring`/`OpenRouterAPIKeyStore` with the shared store
in `OpenRouterUsageProvider`. Update `UsageQuotaStore` construction so the
production `StatusBarController` passes the same cached credential store to
the OpenRouter usage provider; previews/tests may continue using in-memory
stores. When the Keychain is locked or unavailable, return the existing
unavailable quota snapshot with a non-secret status note, not “key missing”
unless the credential truly does not exist.

Keep all public behavior of the Companion CLI session except credential lookup.
Do not add a Gemini quota provider in this step.

**Verify**: `xcodebuild -project GitMenuBar.xcodeproj -scheme GitMenuBar -destination 'platform=macOS' -only-testing:GitMenuBarTests/AICommitCoordinatorTests -only-testing:GitMenuBarTests/UsageQuotaStoreTests -only-testing:GitMenuBarTests/OpenRouterUsageParsingTests test` → exit 0; tests prove one shared OpenRouter identity is used by commit and quota paths.

### Step 5: Record the resolved vocabulary and decision

Update `CONTEXT.md` with concise product terms only, not implementation details:
define **AI provider credential** as the API credential shared by all product
surfaces that call the same backend, and preserve the distinction between
**AI usage quotas** and **AI Commit Generation**. If the one-item Keychain
choice, device-only accessibility, and conflict-preserving migration meet the
ADR criteria, add the next sequential ADR explaining that trade-off; otherwise
keep the rationale in this plan and do not create a speculative ADR.

**Verify**: `make guidance-check` → `guidance-check: passed`; no Markdown link
or plan-schema error is introduced.

## Test plan

- Extend `AIProviderStoreTests` with backend identity and persisted-provider
  compatibility cases.
- Extend or replace `AIKeychainStoreTests` with a deterministic Keychain item
  client fake; cover versioned encode/decode, update/add, missing/locked/error
  status, cache invalidation, and read-modify-write serialization.
- Add migration tests under `GitMenuBarTests/` using injected item state; cover
  validation-before-delete, conflict preservation, retryability and the
  existing GitHub/UserDefaults migration boundaries.
- Extend `AICommitCoordinatorTests` and `UsageQuotaStoreTests` so OpenRouter
  commit and quota consumers read the same credential identity and never write
  local quota snapshots containing credentials.
- Model new tests after `GitMenuBarTests/CredentialStoreCacheTests.swift`,
  `AIProviderStoreTests.swift` and `UsageQuotaStoreTests.swift`; do not use the
  real user's Keychain in automated tests.

## Done criteria

- [ ] One versioned AI-credential blob is the only new persistent item for provider API keys.
- [ ] OpenRouter commit generation and OpenRouter quota resolve the same backend identity.
- [ ] Google/Gemini identity is available for future quota use without adding a quota provider now.
- [ ] Existing UUID-based AI keys and fixed OpenRouter key migrate without silent loss; conflicts remain recoverable.
- [ ] Ambiguous legacy identities are not written to the destination until a
  later explicit conflict-resolution path exists.
- [ ] New blob uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and no secret is logged or persisted in UserDefaults.
- [ ] GitHub token and local Codex/Cursor tokens remain outside the blob.
- [ ] `make test`, `make lint`, `make guidance-check` and `git diff --check` pass.
- [ ] `rg -n 'OpenRouterAPIKeyStore|OpenRouterAPIKeyStoring' GitMenuBar GitMenuBarTests` returns no obsolete storage-type references; the legacy migration reader may retain the literal `provider-` prefix solely to read old items, and historical plans may retain both references.
- [ ] Only files in Scope are modified, aside from the explicitly selected ADR.

## STOP conditions

- The persisted provider list cannot resolve an existing UUID to a backend without a user-visible choice.
- Two legacy values conflict for one backend and the implementation proposes choosing by order, timestamp, or display name.
- The destination blob cannot be reread and verified before legacy deletion.
- A Keychain status is collapsed into “missing key” when it means locked, denied, duplicate or another operational error.
- Sharing the store would require moving GitHub/Codex/Cursor credentials into the AI blob.
- The production app or CLI requires a second Keychain item to keep the chosen behavior.
- The current code has drifted from the excerpts or a targeted test fails twice after a reasonable fix attempt.

## Maintenance notes

### Execution note — 2026-08-05

Implementation shipped in merge `15bfd0e`, with review remediations `05be5d1`
and `abcef63`. The shared Keychain blob, identity resolution, migration
validation and deterministic tests are complete. The legacy
`OpenRouterAPIKeyStoring` compatibility bridge remains temporarily because
`UsageQuotaSettingsSection` is owned by Plan 055; that plan removes the
duplicate quota key editor and the bridge together.

- Any new built-in backend must add one stable credential identity and migration
  test before it is used by commit generation or quotas.
- Keep display names and model names out of credential identity; names are user
  metadata and can change.
- If a future feature needs background quota refresh while the Mac is locked,
  revisit the explicit `WhenUnlockedThisDeviceOnly` trade-off in the ADR rather
  than silently reverting to `AfterFirstUnlock`.
- Reviewers should inspect Keychain status handling, legacy deletion order,
  conflict behavior, cache invalidation, and absence of secret values in logs
  and test fixtures.
- Gemini quota integration is intentionally deferred; this plan only makes the
  shared Google/Gemini credential available.
