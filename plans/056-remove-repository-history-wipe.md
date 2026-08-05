# Plan 056: Remover o recurso Wipe Repository History

> **Executor instructions**: Execute como uma remoção isolada. Elimine a
> superfície de usuário e a implementação de `wipeRepository`, mas preserve
> os fluxos normais de reset, descarte de alterações, histórico e operações
> remotas. Não transforme a remoção em uma refatoração de `GitManager`. Pare
> nas condições de STOP.
>
> **Drift check (run first)**: `git diff --stat 75341b1..HEAD -- GitMenuBar/Pages/Settings/SettingsPage.swift GitMenuBar/Services/Git/GitManager.swift README.md plans/056-remove-repository-history-wipe.md`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: deletion, safety, tech-debt
- **Planned at**: commit `75341b1`, 2026-08-05

## Execution profile

- **Recommended profile**: `implementer-fast`
- **Risk/lane**: `Low/Fast`
- **Parallelizable**: yes — não compartilha arquivos com os Planos 054/055 e
  pode ser executado em uma worktree isolada; a integração final deve revisar
  o conjunto combinado.
- **Reviewer required**: no — a remoção é pequena e verificável por busca,
  compilação e testes; escale se houver chamadas fora do escopo descobertas.
- **Rationale**: o recurso foi explicitamente confirmado como não utilizado e
  a mudança correta é apagar seu caminho inteiro, evitando manter um comando
  destrutivo sem consumidor.
- **Escalate when**: `wipeRepository` ou `RepositoryWipeError` tiver callers
  fora dos arquivos listados, a remoção exigir alterar reset/history comuns,
  ou a compilação revelar que um helper aparentemente específico é compartilhado.

## Why this matters

O recurso atual expõe um comando de alto impacto que recria o histórico, faz
commit e pode forçar push. Como não é usado, manter a UI, os alertas e a
implementação aumenta a superfície de dano e o custo de manutenção sem valor
de produto.

## Current state

- `GitMenuBar/Pages/Settings/SettingsPage.swift:80-161` contém o estado,
  botão de Danger Zone, confirmação, indicador de progresso, erro e chamada a
  `gitManager.wipeRepository`.
- `GitMenuBar/Services/Git/GitManager.swift:12-15` declara
  `RepositoryWipeError`; `:1396-1562` contém o fluxo de backup, orphan branch,
  novo commit, remoção/renomeação de branch e force push.
- `README.md:26,38,118` descreve o recurso na lista de funcionalidades,
  seção de segurança e instruções de uso.
- `docs/code-reviews/019-safe-batch-cleanup.md` e planos concluídos mencionam
  o recurso historicamente. Esses registros são evidência histórica e não
  fazem parte da superfície viva a ser reescrita neste plano.
- Não há testes dedicados ao wipe. A prova principal deve ser ausência de
  callers/strings vivas, compilação e preservação dos testes Git existentes.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Find live references | `rg -n -i 'wipe repository|wipeRepository|RepositoryWipeError|temp_wipe_branch|git-backup-' GitMenuBar README.md` | exit 1; no live matches |
| UI preview | `./scripts/check-preview.sh GitMenuBar/Pages/Settings/SettingsPage.swift` | exit 0; Settings preview remains covered |
| Tests | `make test` | exit 0; XCTest suite passes |
| Lint | `make lint` | exit 0; no new violations |
| Guidance | `make guidance-check` | `guidance-check: passed` |
| Diff hygiene | `git diff --check` | exit 0; no whitespace errors |

The repository-wide `make check-preview` baseline currently fails on a clean
tree because `scripts/check-preview.sh` expands an empty Bash 3.2 array under
`set -u`. Use the explicit Settings file command above and do not fix that
unrelated script in this plan.

## Scope

**In scope** (the only production/user-facing files this plan may modify):

- `GitMenuBar/Pages/Settings/SettingsPage.swift`
- `GitMenuBar/Services/Git/GitManager.swift`
- `README.md`
- `plans/README.md` status/index entry, if the executor maintains the plan ledger

**Out of scope**:

- ordinary reset, discard, checkout, branch, history, pull, push and fetch
  flows;
- generic Git command execution helpers still used by other operations;
- historical completed plans and code-review records;
- unrelated architecture documentation or CI changes;
- new replacement UI or a different repository-history feature.

## Steps

### Step 1: Remove the live settings surface

In `GitSettingsPaneView`, remove only the wipe-specific state, Danger Zone
section, button, confirmation/progress/error presentation and action closure.
Keep the rest of the Settings pane and its preview intact. Re-check all
remaining initializer dependencies before deleting any property: `gitManager`
or other settings dependencies may still serve ordinary Git settings.

**Verify**: `rg -n -i 'wipe repository|wipeRepository|RepositoryWipeError' GitMenuBar/Pages/Settings/SettingsPage.swift` → no matches; the explicit preview command passes.

### Step 2: Delete the unused GitManager implementation

Remove `RepositoryWipeError` and the `wipeRepository` implementation with its
wipe-only backup/orphan-branch/force-push helpers. Before deleting a helper,
search every caller in `GitMenuBar/Services/Git/GitManager.swift` and the rest
of the target; retain any helper used by ordinary Git operations. Do not alter
the semantics of reset, discard, history or remote commands.

**Verify**: `rg -n -i 'wipeRepository|RepositoryWipeError|temp_wipe_branch|git-backup-' GitMenuBar` → no matches; the project compiles through `make test`.

### Step 3: Remove current README promises

Delete the Wipe feature bullet, safety description and usage instructions from
`README.md`. Keep the remaining safety guidance and ordinary repository
history/reset documentation accurate. Do not rewrite historical plan or review
documents to make the deletion appear retroactive.

**Verify**: `rg -n -i 'wipe repository|wipeRepository|repository history.*wipe|wipe.*history' README.md` → no matches; inspect the surrounding README paragraphs for continuity.

### Step 4: Run the narrow deletion gate and record status

Run the commands in the table, then update the plan index only if the project
uses that index for execution status. Record any pre-existing warning or
preview-script limitation without weakening the live-reference check.

**Verify**: all applicable gates pass, and `git diff --check` reports no
whitespace errors. The final diff contains no wipe-specific code, UI or current
README promise.

## Test plan

- No new unit-test fixture is needed for a deleted feature with no dedicated
  tests.
- `make test` must prove that ordinary Git paths still compile and pass.
- The targeted `rg` checks are the regression guard against a dangling
  destructive command or user-facing promise.
- The Settings preview gate must remain covered after removing UI branches.

## Done criteria

- [ ] Settings no longer exposes “Wipe Repository History”, its alert,
  progress state or error state.
- [ ] `RepositoryWipeError`, `wipeRepository` and wipe-only helpers are gone
  from live source, with shared helpers preserved when still referenced.
- [ ] Current README text no longer promises or documents the feature.
- [ ] Ordinary reset, discard, history and remote flows are unchanged.
- [ ] The explicit Settings preview gate, `make test`, `make lint`,
  `make guidance-check` and `git diff --check` pass.
- [ ] Historical completed plans and code-review records remain untouched.
- [ ] Only files in Scope are modified.

## STOP conditions

- A supposedly wipe-only helper is used by reset/history/remote behavior.
- Removing the UI requires changing Settings navigation or unrelated Git
  operations.
- Any ordinary reset, history, discard, pull, push or fetch test changes.
- A user-facing reference remains outside README and its owner is not clearly
  part of this removal; report it instead of broadening scope.
- The current code has drifted from the excerpts or a targeted test fails twice
  after a reasonable fix attempt.

## Maintenance notes

### Execution note — 2026-08-05

Implementação enviada no merge `6e2d3df`, a partir de `83b8550`.
A UI, o fluxo Git e as promessas atuais do README foram removidos; o scan
de referências vivas, preview de Settings, lint e testes passaram.

- Keep historical references in completed plans and reviews unless a separate
  documentation-retention decision asks for a history rewrite.
- If repository-history replacement is requested later, design it as a new,
  separately reviewed feature with explicit backup, recovery and remote-safety
  requirements.
