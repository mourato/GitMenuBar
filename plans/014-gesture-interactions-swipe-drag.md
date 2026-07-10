# Plan 014: Gestos de Interação Direta (swipe e drag)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat abdb924..HEAD -- GitMenuBar/Components/WorkingTree/ GitMenuBar/Components/History/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 013 (recomendado — após a extração das sub-views, o código fica
  mais limpo para adicionar gestos)
- **Category**: direction
- **Planned at**: commit `abdb924`, 2026-07-10

## Why this matters

O app não tem nenhum gesto de drag ou swipe. Todas as interações são clique +
teclado. Swipe para ações rápidas (stage, discard) em file rows e drag para
reordenamento de seções são interações nativas que os usuários esperam em um
app macOS bem construído. Adicionar gestos reduz o número de cliques para
ações frequentes e torna a experiência mais direta.

## Current state

- `WorkingTreeFileRowView` usa `.onTapGesture` para seleção e
  `.onTapGesture(count: 2)` para abrir arquivo. Ações secundárias (stage,
  discard, reveal) estão no `.contextMenu` e em botões de hover.

- `HistoryTimelineRowView` usa `.onTapGesture` para selecionar e contexto para
  ações secundárias.

- Nenhum `.swipeActions` ou `DragGesture` em toda a base.

- `BottomBranchSelectorView` permite apenas clique.

**Convenções do repositório:**
- SwiftUI com `@State` para estado local
- `MacChromeMetrics` para constantes
- Previews para todos os componentes

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `make build`             | exit 0              |
| Tests     | `make test`              | exit 0, all pass    |
| Lint      | `make lint-changed`      | exit 0              |

## Scope

**In scope:**
- `GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift`
- `GitMenuBar/Components/History/HistoryTimelineSectionView.swift`
- `GitMenuBar/Components/Branches/BottomBranchSelector.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift` (se necessário para conectar ações)

**Out of scope:**
- Sheets e popovers
- `StatusBarController`
- Modelos e serviços
- Mudança de comportamento de ações existentes (stage, discard, open continuam funcionando)

## Steps

### Step 1: Swipe-to-stage/unstage em WorkingTreeFileRow

Adicionar `.swipeActions` no `WorkingTreeFileRowView`:

```swift
var body: some View {
    HStack(spacing: 8) {
        // ... conteúdo existente
    }
    // ... modificadores existentes
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button(action: onAction) {
            Label(actionHelp, systemImage: actionIcon)
        }
        .tint(.accentColor)
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
        if let onDiscard {
            Button(role: .destructive, action: onDiscard) {
                Label("Discard", systemImage: "arrow.uturn.backward")
            }
        }
    }
}
```

**Notas:**
- `.swipeActions` está disponível no macOS 13+ (Ventura). Verificar deployment target.
- O swipe da direita faz stage/unstage (ação primária).
- O swipe da esquerda faz discard (destrutivo, sem full swipe).
- `allowsFullSwipe: true` na direita permite que o usuário arraste completamente
  para executar a ação sem soltar.

**Verify**: `make build` → exit 0

### Step 2: Swipe-to-action em HistoryTimelineRowView

Adicionar `.swipeActions` no `HistoryTimelineRowView`:

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    if let commitURL {
        Button {
            NSWorkspace.shared.open(commitURL)
        } label: {
            Label("Open on GitHub", systemImage: "arrow.up.forward.app")
        }
        .tint(.accentColor)
    }
}
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    Button {
        onEditCommitMessage()
    } label: {
        Label("Edit Message", systemImage: "pencil")
    }
    .tint(.orange)
}
```

**Verify**: `make build` → exit 0

### Step 3: Drag para puxar-para-atualizar na timeline (opcional)

Se o deployment target for macOS 14+, considerar adicionar `.refreshable {
... }` na timeline de history para puxar-para-atualizar:

```swift
// No HistorySectionView (após Plan 013) ou em MainMenuContent
.refreshable {
    await gitManager.refreshAsync(includeReflogHistory: false)
}
```

Isso substitui a necessidade do botão "Load 25 more" para refresh completo,
embora o botão ainda seja útil para paginação.

**Nota**: Isso é opcional — se o deployment target for macOS 13, pular este passo.

**Verify**: `make build` → exit 0; testar pull-to-refresh na timeline

### Step 4: Verificar integração com seleção existente

Garantir que swipe não conflita com tap para seleção. O `.swipeActions` do
SwiftUI já gerencia isso corretamente — gestos de swipe são detectados antes
de tap. Verificar que:

- Tap simples ainda seleciona a linha
- Tap duplo ainda abre arquivo/commit detail
- Swipe da direita executa stage/unstage sem selecionar

**Verify**: `make test` → all pass; testar manualmente swipe + tap no preview

## Test plan

- Testes existentes devem continuar passando.
- Verificar manualmente com previews: swipe em file row, swipe em history row.
- Verificar que `.swipeActions` não quebra a seleção por teclado (arrow keys).

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make lint-changed` exits 0
- [ ] `WorkingTreeFileRowView` tem swipe right (stage/unstage) e swipe left (discard)
- [ ] `HistoryTimelineRowView` tem swipe right (open on GitHub) e swipe left (edit message)
- [ ] Tap e teclado continuam funcionando para seleção
- [ ] Nenhum arquivo fora do escopo foi modificado

## STOP conditions

- Se `.swipeActions` não estiver disponível no deployment target, reportar com
  o deployment target mínimo e pular este plano.
- Se houver conflito entre swipe e tap duplo, reportar (`.swipeActions` deve
  ser resolvido pelo sistema, mas pode haver casos extremos).
- Se os arquivos em "Current state" não corresponderem ao código vivo (drift), reportar.

## Maintenance notes

- Novas listas no app (ex: branch list, provider list) devem considerar
  `.swipeActions` como padrão para ações rápidas.
- `allowsFullSwipe: true` só deve ser usado para ações não-destrutivas
  (stage/unstage OK, discard NÃO).
- A cor do `.tint()` deve seguir a semântica: `.accentColor` para ação primária,
  `.orange` para edição, `.red` para destruição, `.green` para sucesso.
