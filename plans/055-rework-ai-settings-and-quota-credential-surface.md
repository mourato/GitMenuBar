# Plan 055: Simplificar a superfície de AI Settings e reutilizar a credencial compartilhada

> **Executor instructions**: Execute depois de Plan 054. O grupo “AI Commit
> Generation” deve terminar com exatamente três itens visíveis, nesta ordem:
> `Default Provider`, `Default Model`, `Add Provider`. O gerenciamento de
> providers existentes acontece dentro da tela aberta por `Add Provider`; não
> reintroduza rows de provider no grupo principal. Não exponha, copie ou registre
> chaves de API. Pare nas condições de STOP.
>
> **Drift check (run first)**: `git diff --stat 75341b1..HEAD -- GitMenuBar/Components/AI GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift GitMenuBar/Services/AI/AIProviderStore.swift GitMenuBarTests scripts/check-preview.sh plans/055-rework-ai-settings-and-quota-credential-surface.md`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/054-consolidate-ai-provider-credentials.md`
- **Category**: tech-debt, correctness, accessibility, tests
- **Planned at**: commit `75341b1`, 2026-08-05

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no — settings ordering, provider management, default-model validity and quota copy depend on the credential contract from Plan 054.
- **Reviewer required**: yes — this changes user-visible settings, destructive provider removal, accessibility labels and the boundary between AI Commit Generation and AI usage quotas.
- **Rationale**: The code change is bounded, but several states currently live in different views and a smaller model could accidentally remove edit/delete access or duplicate credential storage.
- **Escalate when**: the implementation requires a second credential UI, a new quota provider, changes to the settings window navigation, or changes outside the listed files and targeted tests.

## Why this matters

The current AI section renders provider rows, then Add Provider, then the two
default controls, while Usage Quotas owns a second OpenRouter key field. That
duplicates the credential path and contradicts the confirmed settings hierarchy.
The result should keep provider management available, make the three primary
controls predictable, prevent an invalid model after provider changes, and make
OpenRouter quota visibly depend on the shared provider credential.

## Current state

- `GitMenuBar/Components/AI/AISettingsSection.swift:10-55` renders an empty
  message or every `AIProviderRowView`, then `Add Provider`, then default
  pickers. The sheet currently edits one provider at a time.
- `GitMenuBar/Components/AI/AIProviderRow.swift:24-43` exposes Edit/Delete
  actions with `.focusable(false)` and generic labels; deletion immediately
  removes the Keychain value and provider configuration.
- `GitMenuBar/Components/AI/AIProviderEditorSheet.swift:52-65` changes the
  endpoint only when it is empty, and `:138-178` permits save with any non-empty
  API key even after a failed connection test. Saving without a successful test
  is intentional for offline/custom endpoints and must remain allowed.
- `GitMenuBar/Services/AI/AIProviderStore.swift:99-109,148-169` changes the
  default provider but preserves a non-empty `defaultModel` even if it is not
  supported by the new provider.
- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift:3-43`
  owns `openRouterAPIKey` and `OpenRouterAPIKeyStoring`; its `SecureField` is a
  duplicate credential editor. The surrounding toggles remain part of the
  Usage Quotas surface.
- `GitMenuBar/Pages/Settings/SettingsPage.swift:169-193` already keeps
  Companion CLI and Usage Quotas in separate native `Section`s. Do not move or
  merge those sections.
- Plan 054 defines the shared credential lookup by backend identity: stable
  `openrouter`, `google`, `openai`, `anthropic`, or `custom:<provider UUID>`;
  the quota provider reads `openrouter` from the same injected store used by
  commit generation. It does not add Gemini quota support.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Provider/default tests | `xcodebuild -project GitMenuBar.xcodeproj -scheme GitMenuBar -destination 'platform=macOS' -only-testing:GitMenuBarTests/AIProviderStoreTests test` | exit 0; new default-model cases pass |
| Quota tests | `xcodebuild -project GitMenuBar.xcodeproj -scheme GitMenuBar -destination 'platform=macOS' -only-testing:GitMenuBarTests/UsageQuotaStoreTests test` | exit 0; OpenRouter toggle/snapshot cases pass |
| Explicit preview gate | `./scripts/check-preview.sh GitMenuBar/Components/AI/AISettingsSection.swift GitMenuBar/Components/AI/AIProviderManagementSheet.swift GitMenuBar/Components/AI/AIProviderEditorSheet.swift GitMenuBar/Components/AI/AIProviderRow.swift GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift` | exit 0; every listed UI candidate has a preview |
| Full tests | `make test` | exit 0; XCTest suite passes |
| Lint | `make lint` | exit 0; no new violations in touched files |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Diff hygiene | `git diff --check` | exit 0 |

`make check-preview` on a clean tree currently fails before checking files due
to an existing Bash 3.2 empty-array issue in `scripts/check-preview.sh`. Use the
explicit file command above for this plan; do not change that script here.

## Scope

**In scope**:

- `GitMenuBar/Components/AI/AISettingsSection.swift`
- `GitMenuBar/Components/AI/AIProviderManagementSheet.swift` (create)
- `GitMenuBar/Components/AI/AIProviderRow.swift`
- `GitMenuBar/Components/AI/AIProviderEditorSheet.swift`
- `GitMenuBar/Services/AI/AIProviderStore.swift`
- `GitMenuBar/Components/UsageQuota/UsageQuotaSettingsSection.swift`
- targeted files under `GitMenuBarTests/`
- `plans/README.md` status row, maintained by the executor unless a reviewer owns it

**Out of scope**:

- `AIKeychainStore`, migration, backend identity, and production provider
  injection owned by Plan 054
- `GitMenuBar/Pages/Settings/SettingsPage.swift` navigation or section taxonomy
- Gemini quota provider, new quota toggles, status-item quota UI, or snapshot format
- new Settings search/sidebar/navigation
- `scripts/check-preview.sh`; use the explicit-file gate until a separate DX plan fixes its clean-tree bug

## Steps

### Step 1: Make the main AI section contain only the three confirmed controls

Refactor `AISettingsSectionView` so its body renders, in source and runtime
order:

1. `Default Provider` picker;
2. `Default Model` picker/value;
3. `Add Provider` button.

Remove the provider `ForEach`, the standalone empty-state text, and any other
visible row from this section. Keep the existing bindings to
`AIProviderStore.preferences`. When no provider exists, keep the two semantic
rows present but disabled with a concise native placeholder; do not add a
fourth empty-state row. The Add Provider button remains enabled and opens the
provider-management sheet.

**Verify**: inspect the view source and run the explicit preview gate → the
three controls are the only direct children of the main AI section and the
listed UI candidates have preview coverage.

### Step 2: Add the provider-management sheet behind Add Provider

Create `AIProviderManagementSheet.swift` with a focused `#Preview`. It must:

- list configured providers using the existing `AIProviderRowView` pattern;
- offer Edit, which opens the existing `AIProviderEditorSheet` for that provider;
- offer Add Provider, which opens the existing editor for a new provider;
- offer Delete only after a native confirmation alert, then delete the shared
  backend credential only when no remaining provider references it;
- preserve the current default-provider normalization when the deleted provider
  was default;
- show a useful empty state inside the management sheet only, not in the main
  AI Commit Generation section;
- keep button labels and accessibility labels provider-specific, for example
  “Edit Gemini” and “Delete OpenRouter”, instead of repeated unlabeled Edit/Delete
  actions.

Do not create a second provider model or a second Keychain store. Reuse
`AIProviderStore`, `AICommitCoordinator`/the shared credential store and
`AIProviderRowView`.

**Verify**: the management-sheet preview renders empty and populated states;
`make lint` → exit 0 with no new warnings in these files.

### Step 3: Preserve valid defaults when the provider changes

Update `AIProviderStore.updateDefaultProvider(_:)` and the normalization path
so a non-empty `defaultModel` is retained only if it is valid for the newly
selected provider. If it is invalid, choose the provider’s selected model,
then its first available model, otherwise clear the value. Keep existing
persisted preferences backward-compatible.

Add tests for:

- switching from provider A to B with the same model available;
- switching to a provider that does not advertise the old model;
- switching to a provider with no model list but a selected model;
- deleting the default provider and normalizing the replacement;
- empty provider storage.

**Verify**: targeted `AIProviderStoreTests` command → exit 0 and all new cases
pass.

### Step 4: Make provider editing preserve deliberate custom endpoints

In `AIProviderEditorSheet`, update the endpoint automatically only when the
current endpoint is still the previous provider type’s built-in default (or the
new-provider default). If the user edited a custom endpoint, changing the
provider type must preserve it. Keep saving a non-empty key allowed even when
`Test Connection` failed; a transient network failure must not prevent an
offline/custom provider from being saved.

Consume the error-aware save result from Plan 054: do not dismiss or update the
provider configuration when the shared credential write fails; show a generic,
non-secret error and let the user retry. Never put the failed key in the error
message.

**Verify**: editor tests or extracted pure endpoint-transition tests → exit 0;
manual preview confirms custom endpoint preservation and save errors do not
dismiss the editor.

### Step 5: Remove the duplicate OpenRouter key editor from Usage Quotas

Delete the `openRouterAPIKey` state, `OpenRouterAPIKeyStoring` dependency and
`SecureField` from `UsageQuotaSettingsSection`. Keep the parent and provider
toggles, refresh action, and privacy explanation. Replace the obsolete key-copy
sentence with concise copy stating that OpenRouter quota uses the OpenRouter
provider credential configured in AI settings. If no such credential exists,
the quota provider should report an unavailable non-secret state; this plan
does not add a new field or Gemini quota provider.

Update the preview to use the shared in-memory credential store/injected quota
provider from Plan 054. Add or update quota tests so toggling OpenRouter still
controls visibility and refreshing does not create a second credential path.

**Verify**: targeted `UsageQuotaStoreTests` command and explicit preview gate →
both exit 0.

### Step 6: Audit accessibility and preview states

Remove `.focusable(false)` from provider-management actions unless a specific
AppKit reason is demonstrated. Give every repeated action an accessible label
containing the provider name, preserve visible labels, and ensure disabled
default controls remain understandable to VoiceOver and keyboard users. Keep
previews for every new or changed UI-rendering Swift file; use a companion
preview only in the same directory.

**Verify**: explicit preview gate, `make lint` and manual keyboard/VoiceOver
smoke test → no missing preview and each provider action is identifiable.

## Test plan

- Model `AIProviderStoreTests` additions after its existing in-memory data-store
  setup; assert persisted preferences and provider identity, not implementation
  details.
- Add pure tests for endpoint transition behavior if the logic is extracted;
  do not introduce UI snapshot infrastructure solely for this change.
- Extend `UsageQuotaStoreTests` with shared-store injection and OpenRouter
  unavailable/available cases; keep Codex/Cursor local-token behavior unchanged.
- Use the existing `#Preview` blocks in `AISettingsSection.swift`,
  `AIProviderEditorSheet.swift`, `AIProviderRow.swift` and
  `UsageQuotaSettingsSection.swift` as structural patterns.
- Manual acceptance: the main section shows exactly the three requested items
  in the requested order; Add Provider opens management; existing providers can
  be edited/deleted with confirmation; OpenRouter quota has no duplicate key
  field and uses the configured provider credential.

## Done criteria

- [ ] Main “AI Commit Generation” section has exactly `Default Provider`, `Default Model`, `Add Provider`, in that order.
- [ ] Existing providers remain manageable through the Add Provider sheet.
- [ ] Provider deletion is confirmed and does not delete a shared credential still used by another provider.
- [ ] Switching the default provider cannot leave an invalid default model.
- [ ] Custom endpoints survive provider-type changes when intentionally edited.
- [ ] Failed Keychain writes do not dismiss the editor or mutate provider metadata.
- [ ] Usage Quotas has no API-key field and uses the shared OpenRouter credential path.
- [ ] Accessibility labels identify each provider action and direct keyboard/VoiceOver interaction remains possible.
- [ ] Every changed/new UI file has a preview; the explicit preview gate passes.
- [ ] `make test`, `make lint`, `make guidance-check` and `git diff --check` pass.
- [ ] Only files in Scope are modified.

## STOP conditions

- The three-item order requires adding a visible provider-management row to the main section.
- Existing providers become impossible to edit or delete without opening a hidden/unlabeled control.
- Deleting one provider would remove a backend credential still referenced by another provider.
- The implementation blocks save solely because a network test failed.
- The shared credential write API from Plan 054 is unavailable or still silently swallows persistence errors.
- A UI file lacks a preview or the explicit preview command fails because of the change rather than the known clean-tree script baseline.
- The current code has drifted from the excerpts or a targeted test fails twice after a reasonable fix attempt.

## Maintenance notes

### Execution note — 2026-08-05

Implementation shipped in merge `4e04a67`, with review remediation `e245e00`.
The main AI section now contains only the three confirmed controls, provider
management is behind Add Provider, quota settings consume the shared
OpenRouter credential, and the obsolete adapter types were removed. Manual
VoiceOver smoke testing remains for a native macOS session.

- Keep provider-management navigation behind the existing Add Provider affordance
  unless a later product decision changes the three-item contract.
- Any new backend must update identity resolution, default-model validity and
  provider-specific accessibility labels together.
- Do not reintroduce a quota-specific API-key field; quota providers should
  consume the shared credential store.
- A separate DX plan may make `make check-preview` safe on a clean Bash 3.2
  tree; this plan intentionally uses explicit files and does not touch that
  script.
- Reviewers should inspect deletion confirmation, shared-credential reference
  counting, default-model reset behavior, error copy and VoiceOver labels.
