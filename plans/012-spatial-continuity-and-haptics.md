# Plan 012: Continuidade Espacial e Feedback Multimodal

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: no; the scope does not require a separate review by default.
- **Rationale**: Integra animações e feedback em superfícies delimitadas; exige julgamento de interação.
- **Escalate when**: Se introduzir sincronização concorrente, novo estado persistente ou ciclo de vida global.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat abdb924..HEAD -- GitMenuBar/Components/ GitMenuBar/Pages/MainMenu/ GitMenuBar/App/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `abdb924`, 2026-07-10

## Why this matters

Este plano agrupa duas iniciativas complementares que tornam a navegação no app
mais conectada e expressiva:

1. **Continuidade espacial** — hoje as transições entre telas (timeline → commit
   detail, header → popover) não têm conexão visual. O `matchedGeometryEffect`
   permite que elementos "voem" de um contexto para outro, dando ao usuário a
   sensação de que é o mesmo objeto sendo transformado.

2. **Feedback háptico** — ações importantes (commit, stage, sync, erro) não têm
   confirmação tátil. MacBooks com Force Touch e Magic Trackpads suportam
   `NSHapticFeedbackManager`. Adicionar haptics sutis em momentos-chave aumenta
   a sensação de solidez e resposta.

## Current state

### matchedGeometryEffect

- Zero uso de `matchedGeometryEffect` em toda a base de código.
- `HistoryTimelineRowView` → `CommitDetailPageView`: transição sem nenhuma
  conexão visual. Quando o usuário dá double-tap em um commit, a view de detalhes
  simplesmente aparece (via troca de rota no `switch`).
- `MainMenuHeaderView` → `ProjectSelectorPopover`: popover aparece sem conexão
  visual com o botão de projeto.
- `MainMenuHeaderView` → `RepositoryOptionsPopoverView`: mesma situação.

### Haptic feedback

- `NSSound.beep()` é usado em `MainMenuCommandPalette.swift:295` e `303` para
  indicar item desabilitado.
- Nenhum `NSHapticFeedbackManager` em toda a base.
- Nenhum outro feedback não-visual para ações como commit, stage, sync.

**Convenções do repositório:**
- `@EnvironmentObject` para dependências
- SwiftUI com `switch` para navegação de rotas
- `MainMenuPresentationModel` gerencia rotas

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `make build`             | exit 0              |
| Tests     | `make test`              | exit 0, all pass    |
| Lint      | `make lint-changed`      | exit 0              |

## Scope

**In scope:**
- `GitMenuBar/Components/History/HistoryTimelineSectionView.swift`
- `GitMenuBar/Components/History/CommitDetailPageView.swift`
- `GitMenuBar/Components/Common/MainMenuHeaderView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift`
- `GitMenuBar/Components/Common/CommitComposer.swift`

**Out of scope:**
- Sheets (apresentação nativa do sistema)
- `StatusBarController` e lógica AppKit de badge/context menu
- Modelos e serviços
- Criação de novos serviços

## Steps

### Step 1: matchedGeometryEffect — timeline → commit detail

Em `MainMenuView`, adicionar um `@Namespace private var animation` no topo da struct.

Em `HistoryTimelineRowView`, adicionar `matchedGeometryEffect` no título do commit:

```swift
// HistoryTimelineRowView — no VStack do subject (linha ~104)
VStack(alignment: .leading, spacing: 4) {
    Text(commit.subject)
        .font(.system(size: 13, weight: .medium))
        .matchedGeometryEffect(id: "commit-\(commit.id)", in: animation) // namespace precisa ser passado como parâmetro
        // ...
}
```

Em `CommitDetailPageView`, adicionar `matchedGeometryEffect` correspondente no título:

```swift
// CommitDetailPageView — no subject (linha ~124)
Text(commit.subject)
    .font(.system(size: 15, weight: .semibold))
    .matchedGeometryEffect(id: "commit-\(commit.id)", in: animation)
```

**Nota de implementação**: O `animation` namespace precisa ser passado de
`MainMenuView` para `HistoryTimelineSectionView` e `CommitDetailPageView`.
A abordagem mais limpa: criar um `@StateObject` ou `@EnvironmentObject` que
segure o namespace (ex: `MainMenuAnimationNamespace`), ou simplesmente passar
como parâmetro `let animationNamespace: Namespace.ID`.

Abordagem recomendada: adicionar o namespace em `MainMenuView` e passá-lo como
parâmetro `animationNamespace` para as subviews que precisam:

```swift
// MainMenuView
@Namespace private var animationNamespace
```

E nas chamadas de subview:

```swift
// Em HistoryTimelineSectionView
HistoryTimelineSectionView(
    sections: historyTimelineSections,
    animationNamespace: animationNamespace, // novo parâmetro
    // ...
)

// Em CommitDetailPageView
CommitDetailPageView(
    commit: ...,
    animationNamespace: animationNamespace, // novo parâmetro
    // ...
)
```

**Verify**: `make build` → exit 0

### Step 2: matchedGeometryEffect — header → popover

Em `MainMenuHeaderView`, adicionar `matchedGeometryEffect` no botão de projeto:

```swift
// No botão do projeto
.matchedGeometryEffect(id: "projectSelector", in: animationNamespace)
```

Dentro do `ProjectSelectorPopoverView`, no container principal:

```swift
.matchedGeometryEffect(id: "projectSelector", in: animationNamespace)
```

Isso faz o popover "crescer" a partir do botão em vez de simplesmente aparecer.

**Verify**: `make build` → exit 0

### Step 3: Adicionar haptics em ações-chave

Criar um helper em `MacChromeMetrics.swift` (ou novo arquivo
`Components/Common/HapticFeedback.swift`):

```swift
import AppKit

enum HapticFeedback {
    /// Toca um feedback háptico se o hardware suportar (MacBook Force Touch,
    /// Magic Trackpad).
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard NSHapticFeedbackManager.isAvailable else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
```

Adicionar haptics nos seguintes pontos:

**CommitComposer — após commit bem-sucedido** (`MainMenuActions.swift`):
```swift
HapticFeedback.perform(.levelChange) // sensação de confirmação
```

**Stage/Unstage** (`WorkingTreeFileRow` ou `MainMenuActions`):
```swift
HapticFeedback.perform(.generic) // toque leve
```

**Sync/Commit & Push** (`MainMenuActions`):
```swift
HapticFeedback.perform(.levelChange) // confirmação
```

**Erro** (nos handlers de erro dos alerts):
```swift
HapticFeedback.perform(.warning) // aviso
```

**Command palette — item desabilitado** (`MainMenuCommandPalette:295`):
Substituir `NSSound.beep()` por:
```swift
HapticFeedback.perform(.generic)
```

**Verify**: `make build` → exit 0; testar commit, stage, sync com o app em
primeiro plano (haptics funcionam apenas quando o app está ativo)

### Step 4: Verificar integração

Garantir que os haptics são disparados no mesmo frame da animação de sucesso,
conforme o princípio Apple de causalidade:

```swift
// Padrão correto — haptic + animação no mesmo frame
HapticFeedback.perform(.levelChange)
withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
    // mudança de estado visual
}
```

Verificar que nenhum haptic está solto em um callback assíncrono separado
(ex: dentro de um `Task { }` após um `try await`).

**Verify**: `make build` → exit 0

## Test plan

- Testes existentes devem continuar passando.
- `matchedGeometryEffect` não muda comportamento funcional — apenas animação.
- Haptics não têm efeito colateral além do feedback tátil.
- Verificar visualmente a transição timeline → commit detail nos previews.

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make lint-changed` exits 0
- [ ] `matchedGeometryEffect` conecta timeline → commit detail
- [ ] `matchedGeometryEffect` conecta header → popover de projeto
- [ ] `HapticFeedback` helper existe e é chamado em commit, stage, sync, erro
- [ ] `NSSound.beep()` substituído por haptic no command palette
- [ ] Nenhum arquivo fora do escopo foi modificado

## STOP conditions

- Se `matchedGeometryEffect` causar artefatos visuais (elementos sobrepostos,
  tamanhos incorretos), reduzir o escopo — reportar se não resolver em 2 tentativas.
- Se o haptic não funcionar no preview/test (esperado — haptics só funcionam
  em app rodando), não bloquear — reportar como nota.
- Se os arquivos em "Current state" não corresponderem ao código vivo (drift), reportar.

## Maintenance notes

- `matchedGeometryEffect` deve ser usado em qualquer transição futura onde um
  elemento aparece em dois contextos (ex: card → detail).
- Haptics devem sempre ser disparados no mesmo frame da animação de feedback
  visual, nunca em callbacks separados.
- O `HapticFeedback` helper pode ser expandido com padrões específicos
  (`.alignment`, `.levelChange`, `.generic`, `.warning`) conforme necessário.
