# Plan 009: Adicionar feedback de pressão, springs e suporte a Reduce Motion

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat abdb924..HEAD -- GitMenuBar/Components/ GitMenuBar/Pages/MainMenu/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P0
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `abdb924`, 2026-07-10

## Why this matters

O app não dá feedback visual imediato quando o usuário toca/clica em elementos
interativos — a resposta só aparece após o gesto terminar. Toda animação usa
`easeInOut` com duração fixa (não responsiva a interrupções). E nenhuma transição
respeita a preferência `Reduce Motion` de acessibilidade. Isso faz a interface
parecer "morta" sob o dedo e quebra as diretrizes Apple de resposta e
interruptibilidade.

## Current state

- Todos os botões e linhas clicáveis usam `.onTapGesture { }` ou `Button` padrão —
  sem highlight no touch-down. Exemplo em `WorkingTreeFileRowView:60-65`:
  ```swift
  .onTapGesture {
      onSelect?()
  }
  .onTapGesture(count: 2) {
      onOpen?()
  }
  ```

- A única animação explícita no app está em `MainMenuCommandPaletteView:277`:
  ```swift
  withAnimation(.easeInOut(duration: 0.15)) {
      performScroll()
  }
  ```

- `BottomBranchSelector` desativa animação com `.animation(nil, value:)`.

- Seções colapsáveis (staged, unstaged, history) em `MainMenuContent.swift` usam
  `if !isCollapsed { ... }` sem animação de transição.

- Transições de rota (main → create repo → history detail) em `MainMenuView:111-154`
  usam `switch` sem animação.

- `MainMenuCommandPaletteView` é o único componente que respeita
  `@Environment(\.accessibilityReduceMotion)`. Nenhum outro componente verifica.

**Convenções do repositório:**
- SwiftUI com `@EnvironmentObject` para injeção de dependência
- `MacChromeMetrics` para constantes de layout
- `MacChromePalette` para cores
- Previews em todos os arquivos de UI

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
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Components/Common/MacChromeMetrics.swift` (se precisar adicionar constantes de animação)
- `GitMenuBar/Components/Common/CommitComposer.swift`

**Out of scope:**
- Sheets e popovers (têm apresentação padrão do sistema)
- `StatusBarController` e lógica AppKit
- Criação de novos arquivos (salvo se necessário para `PressableButtonStyle`)

## Steps

### Step 1: Criar `PressableButtonStyle` e aplicá-lo

Criar um `ButtonStyle` que escala o botão ligeiramente no pressionar:

```swift
// Em MacChromeMetrics.swift ou novo arquivo Components/Common/PressableButtonStyle.swift
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 1.0), value: configuration.isPressed)
    }
}
```

Em `WorkingTreeFileRowView`, adicionar feedback visual no `onTapGesture`:
- Usar `DragGesture(minimumDistance: 0)` com `updating` para um `@GestureState` que
  escala a row em 0.97 no began/changed, e executa a ação no ended.
- Ou, mais simplesmente, usar o `PressableButtonStyle` se o row for convertido para `Button`.

No `HistoryTimelineRowView`, mesma abordagem: feedback no toque inicial, não
apenas no release.

**Verify**: `make build` → exit 0

### Step 2: Substituir easeInOut por spring no command palette

Em `MainMenuCommandPaletteView:277`:

**Antes:**
```swift
withAnimation(.easeInOut(duration: 0.15)) {
    performScroll()
}
```

**Depois:**
```swift
withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
    performScroll()
}
```

Remover o fallback `DispatchQueue.main.asyncAfter` não-animado (linhas 282-284)
— com spring, o scroll é preciso e a segunda chamada não é mais necessária.

**Verify**: `make build` → exit 0; testar command palette keyboard navigation

### Step 3: Adicionar spring em collapses de seção

Em `MainMenuContent.swift`, nas seções staged/unstaged/history, adicionar
transição animada para o `if !isCollapsed { ... }`:

```swift
if !isStagedSectionCollapsed {
    VStack(spacing: 3) {
        // ... conteúdo
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
}
```

E no `withAnimation` ao alternar o collapse (nos headers):

```swift
withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
    isStagedSectionCollapsed.toggle()
}
```

**Verify**: `make build` → exit 0; testar collapse de seções

### Step 4: Adicionar transição animada nas trocas de rota

Em `MainMenuView:110-154`, adicionar `.transition()` no `switch`:

```swift
switch presentationModel.route {
case .main:
    mainView.transition(.opacity.combined(with: .move(edge: .bottom)))
case .createRepo:
    // ...
case .historyDetail:
    // ...
}
```

E garantir que o container `VStack` tenha `.animation(.spring(response: 0.35, dampingFraction: 1.0), value: presentationModel.route)`.

**Verify**: `make build` → exit 0; testar navegação entre telas

### Step 5: Adicionar `reduceMotion` em todas as transições

Criar um `ViewModifier` reutilizável em `MacChromeMetrics.swift` ou novo arquivo:

```swift
struct AdaptiveTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
    }
}

extension View {
    func adaptiveMotion() -> some View {
        modifier(AdaptiveTransition())
    }
}
```

Aplicar `.adaptiveMotion()` no `VStack` raiz de `MainMenuView` e em qualquer
lugar com `.animation()` ou `.transition()`.

**Verify**: `make build` → exit 0; ativar Reduce Motion nas Prefs do Sistema →
verificar que collapses e transições viram cross-fade sem spring

## Test plan

- Os testes existentes devem continuar passando — este plano não muda lógica de
  negócio, apenas animação/feedback.
- Verificar visualmente cada cena nos previews:
  - `WorkingTreeFileRow` preview → pressionar e ver scale
  - `HistoryTimelineSectionView` preview → pressionar e ver feedback
  - `MainMenuCommandPalette` preview → scroll com spring
- Nenhum teste novo necessário (são mudanças puramente visuais).

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make lint-changed` exits 0
- [ ] Botões e linhas têm feedback visual no touch-down
- [ ] Nenhum `.easeInOut` permanece no código (grep confirm)
- [ ] `@Environment(\.accessibilityReduceMotion)` é respeitado pelo container principal
- [ ] Nenhum arquivo fora do escopo foi modificado

## STOP conditions

- Se `make build` falhar, ler o erro e tentar corrigir; se persistir após 2 tentativas, reportar.
- Se algum teste existente falhar, identificar se a mudança causou a regressão; se sim, reportar.
- Se o arquivo em "Current state" não corresponder ao código vivo (drift), reportar.

## Maintenance notes

- Novos componentes devem seguir o padrão `PressableButtonStyle` para consistência.
- Novas transições devem usar `.spring(response:dampingFraction:)` em vez de `.easeInOut`.
- O `AdaptiveTransition` modifier deve ser aplicado em qualquer nova view raiz.
