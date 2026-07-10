# Plan 010: Hierarquia Visual com Materiais e Sombras

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

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `abdb924`, 2026-07-10

## Why this matters

O app usa `.regularMaterial` para painéis, mas não diferencia a hierarquia de
superfícies com pesos de material distintos. A cortina do command palette é uma
cor sólida (não material). O `CommitHoverCardView` usa cor sólida opaca em vez
de material translúcido. Não há sombras proporcionais ao peso da superfície.
Isso achata a hierarquia visual e faz o app parecer menos nativo no macOS.

## Current state

- `CommitHoverCardView:24-25` — fundo opaco sem material:
  ```swift
  .background(
      RoundedRectangle(cornerRadius: 12)
          .fill(Color(nsColor: .controlBackgroundColor))
  )
  ```

- `MainMenuOverlays:211-212` — scrim do command palette é cor sólida:
  ```swift
  Color(nsColor: .windowBackgroundColor).opacity(0.28)
      .ignoresSafeArea()
  ```

- `MainMenuCommandPaletteView:160-168` — shadow fixa `radius: 16, y: 8`:
  ```swift
  .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
  ```

- `InlineStatusBannerView:80` — estilo `.info` usa cor sólida:
  ```swift
  return Color(nsColor: .controlBackgroundColor)
  ```

- `MainMenuHeaderView` — sem background material.

- `MacPanelSurface` usa `.regularMaterial` para todos os painéis sem variação.

- A janela principal não tem material de fundo global — o conteúdo usa
  `.regularMaterial` do `MacPanelSurface`, mas o fundo da janela em si não.

- Nenhum componente tem sombra além do command palette.

**Convenções:**
- `MacPanelSurfaceModifier` em `MacPanelSurface.swift` — view modifier para
  fundo com material + corner radius
- `MacChromePalette` em `MacChromeMetrics.swift` — cores com contraste
- `MacChromeMetrics` — corner radii padronizados

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `make build`             | exit 0              |
| Tests     | `make test`              | exit 0, all pass    |
| Lint      | `make lint-changed`      | exit 0              |

## Scope

**In scope:**
- `GitMenuBar/Components/History/CommitHoverCardView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift`
- `GitMenuBar/Components/Common/InlineStatusBannerView.swift`
- `GitMenuBar/Components/Common/MainMenuHeaderView.swift`
- `GitMenuBar/Components/Common/MacPanelSurface.swift`
- `GitMenuBar/Components/Common/MacChromeMetrics.swift` (constantes de sombra)

**Out of scope:**
- Sheets (são apresentação padrão do sistema)
- Botões e texto (cobertos em outros planos)
- Alteração de layout ou padding

## Steps

### Step 1: Hierarquia de materiais — `MacPanelSurface`

Expandir `MacPanelSurfaceModifier` para aceitar peso de material:

```swift
private struct MacPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let materialWeight: MaterialWeight  // novo enum

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(backgroundFill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var backgroundFill: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else {
            switch materialWeight {
            case .thin:    shape.fill(.thinMaterial)
            case .regular: shape.fill(.regularMaterial)
            case .thick:   shape.fill(.thickMaterial)
            }
        }
    }
}

enum MaterialWeight {
    case thin, regular, thick
}

extension View {
    func macPanelSurface(
        cornerRadius: CGFloat = MacChromeMetrics.largeCornerRadius,
        material: MaterialWeight = .regular
    ) -> some View {
        modifier(MacPanelSurfaceModifier(cornerRadius: cornerRadius, materialWeight: material))
    }
}
```

**Verify**: `make build` → exit 0

### Step 2: CommitHoverCard — thickMaterial + sombra

Em `CommitHoverCardView.swift`, substituir o fundo opaco por `.thickMaterial` e
adicionar sombra proporcional:

**Antes:**
```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color(nsColor: .controlBackgroundColor))
)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
)
```

**Depois:**
```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(.thickMaterial)
)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
)
.shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 10)
```

**Verify**: `make build` → exit 0; preview do hover card deve mostrar material translúcido

### Step 3: Scrim do command palette — ultraThinMaterial

Em `MainMenuOverlays.swift:211-212`:

**Antes:**
```swift
Color(nsColor: .windowBackgroundColor).opacity(0.28)
    .ignoresSafeArea()
```

**Depois:**
```swift
Rectangle()
    .fill(.ultraThinMaterial)
    .ignoresSafeArea()
```

**Verify**: `make build` → exit 0; scrim deve mostrar blur sutil

### Step 4: Command palette — shadow ajustada

A shadow atual `radius: 16, y: 8` está adequada. Apenas garantir que o material
continue `.regularMaterial` (já está). Sem mudanças.

**Verify**: verificar que o comando palette já usa `.regularMaterial`

### Step 5: InlineStatusBanner — info com thinMaterial

Em `InlineStatusBannerView.swift:80`:

**Antes:**
```swift
return Color(nsColor: .controlBackgroundColor)
```

**Depois:**
```swift
return Color(nsColor: .controlBackgroundColor) // fallback quando reduceTransparency
// No ramo normal do banner .info, usar .thinMaterial:
// A lógica precisa de refatoração — o backgroundColor atual é um Color computado.
// Melhor abordagem: tornar o banner um retângulo com overlay de material.
```

**Abordagem recomendada**: Envolver o banner inteiro em `.background(.thinMaterial)` e
remover o `backgroundColor` customizado para o caso `.info`. Manter os backgrounds
customizados para `.warning` e `.error` (que usam cores semânticas).

**Verify**: `make build` → exit 0; preview do banner .info deve mostrar material sutil

### Step 6: MainMenuHeaderView — fundo sutil com thinMaterial

Em `MainMenuHeaderView.swift`, adicionar background material ao `HStack` principal:

```swift
var body: some View {
    HStack(spacing: MacChromeMetrics.compactSpacing) {
        // conteúdo existente
    }
    .padding(.horizontal, MacChromeMetrics.panelPadding)
    .padding(.vertical, 6)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacChromeMetrics.cornerRadius, style: .continuous))
}
```

**Verify**: `make build` → exit 0; header deve mostrar superfície sutilmente separada do conteúdo

## Test plan

- Todos os testes existentes devem continuar passando.
- Verificar visualmente cada componente nos previews:
  - `CommitHoverCardView` → material translúcido com sombra
  - `InlineStatusBannerView` → banner .info com thinMaterial
  - `MainMenuHeaderView` → fundo sutil
- Nenhum teste novo necessário.

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make lint-changed` exits 0
- [ ] `CommitHoverCardView` usa `.thickMaterial` em vez de cor sólida
- [ ] Scrim do command palette usa `.ultraThinMaterial`
- [ ] `InlineStatusBannerView` estilo `.info` usa `.thinMaterial`
- [ ] `MainMenuHeaderView` tem fundo `.thinMaterial`
- [ ] `MacPanelSurface` aceita parâmetro `materialWeight` (thin/regular/thick)
- [ ] Nenhum arquivo fora do escopo foi modificado

## STOP conditions

- Se `make build` falhar, ler o erro e tentar corrigir; se persistir após 2 tentativas, reportar.
- Se o preview de algum componente ficar visualmente quebrado (e.g., material over conteúdo não-legível), reportar.
- Se os arquivos em "Current state" não corresponderem ao código vivo (drift), reportar.

## Maintenance notes

- Novos cards flutuantes (popovers, hover cards, sheets customizados) devem usar
  `.thickMaterial` com sombra `radius: 20, y: 10`.
- Novos painéis de fundo (headers, toolbars) devem usar `.thinMaterial`.
- A escolha do material deve seguir: thin → superfície de fundo, regular → painel
  de conteúdo, thick → card flutuante/popover.
- A shadow deve escalar com a hierarquia: cards flutuantes > painéis > headers.
