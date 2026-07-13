# Plan 011: Tipografia Adaptativa com Dynamic Type e Tracking

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: no; the scope does not require a separate review by default.
- **Rationale**: Mudança visual com efeitos em layout e legibilidade que requer validação contextual.
- **Escalate when**: Se tocar navegação, persistência, acessibilidade sistêmica ou várias telas fora do escopo.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat abdb924..HEAD -- GitMenuBar/`
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

O app usa tamanhos de fonte fixos (`system(size: 12, weight: .semibold)`) em
quase toda a base. Isso significa que: (1) usuários que aumentam o texto do
sistema (Dynamic Type) não veem adaptação; (2) a tipografia não tem o tracking
(kerning) correto por tamanho — texto grande fica espaçado demais, texto pequeno
fica apertado; (3) não há consistência entre fontes — metade usa
`MacChromeTypography`, metade usa `.system(size:)` diretamente.

## Current state

- `MacChromeTypography` (linhas 16-47 de `MacChromeMetrics.swift`) define fontes
  com `Font.headline`, `.body`, etc. — é o padrão correto, mas é ignorado em
  grande parte do código.

- Uso extensivo de `.system(size:)` fixo:
  - `WorkingTreeFileRow.swift:93`: `.font(.system(size: 13, weight: .regular))`
  - `WorkingTreeFileRow.swift:100`: `.font(.system(size: 11, weight: .light))`
  - `HistoryTimelineSectionView.swift:108`: `.font(.system(size: 13, weight: .medium))`
  - `HistoryTimelineSectionView.swift:49`: `.font(.system(size: 12, weight: .semibold))`
  - `CommitDetailPageView.swift:124`: `.font(.system(size: 15, weight: .semibold))`
  - `CommitHoverCardView.swift:58`: `.font(.system(size: 14, weight: .semibold))`
  - Dezenas de outras ocorrências.

- Nenhum `.tracking()` em toda a base.

- Nenhum `.dynamicTypeSize(...)` modificador.

- Nenhum `@ScaledMetric` para espaçamentos que acompanham tamanho de texto.

- `BottomBranchSelector` usa `.font(.system(size: 11))` com `.monospacedDigit()`.

**Convenções do repositório:**
- `MacChromeTypography` como enum de fontes — deve ser a fonte da verdade
- `MacChromeMetrics` para constantes de layout
- Previews em todos os arquivos

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `make build`             | exit 0              |
| Tests     | `make test`              | exit 0, all pass    |
| Lint      | `make lint-changed`      | exit 0              |

## Scope

**In scope (todos os arquivos que usam `.system(size:)`):**
- `GitMenuBar/Components/WorkingTree/WorkingTreeFileRow.swift`
- `GitMenuBar/Components/History/HistoryTimelineSectionView.swift`
- `GitMenuBar/Components/History/CommitDetailPageView.swift`
- `GitMenuBar/Components/History/CommitHoverCardView.swift`
- `GitMenuBar/Components/History/CommitHoverCardView.swift`
- `GitMenuBar/Components/Common/CommitComposer.swift`
- `GitMenuBar/Components/Common/InlineStatusBannerView.swift`
- `GitMenuBar/Components/Common/MainMenuHeaderView.swift`
- `GitMenuBar/Components/Branches/BottomBranchSelector.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuCommandPalette.swift`
- `GitMenuBar/Components/Common/MacChromeMetrics.swift` (adicionar tracking helpers)

**Out of scope:**
- Sheets (usam fontes do sistema por default)
- Modelos e serviços (sem UI)
- Lógica de negócio
- Constantes de layout que não são de texto (`panelPadding`, `windowPadding`, etc.)

## Steps

### Step 1: Expandir `MacChromeTypography` com tracking

Adicionar tracking por contexto de tamanho em `MacChromeMetrics.swift`:

```swift
enum MacChromeTypography {
    // ... existentes ...

    /// Tracking (letter-spacing) por contexto de tamanho.
    /// Apple: display text wants negative tracking; small text wants slightly positive.
    static func tracking(for font: Font) -> CGFloat {
        // Valores empíricos para San Francisco
        // Tamanhos grandes (title, largeTitle): -0.5 a -1.0
        // Tamanhos médios (headline, body): 0.0 a 0.1
        // Tamanhos pequenos (caption, footnote): 0.2 a 0.3
        switch font {
        case .largeTitle: return -1.0
        case .title, .title2: return -0.5
        case .headline: return 0.0
        case .body: return 0.1
        case .callout: return 0.1
        case .subheadline: return 0.15
        case .footnote: return 0.2
        case .caption, .caption2: return 0.3
        default: return 0.0
        }
    }
}
```

**Verify**: `make build` → exit 0

### Step 2: Substituir `.system(size:)` por `MacChromeTypography` em WorkingTreeFileRow

Fazer `WorkingTreeFileRow.swift` usar `MacChromeTypography`:

| Localização | Antes | Depois |
|------------|-------|--------|
| file name (linha 93) | `.font(.system(size: 13, weight: .regular))` | `.font(MacChromeTypography.body)` |
| directory path (linha 100) | `.font(.system(size: 11, weight: .light))` | `.font(MacChromeTypography.caption)` |
| WorkingTreeLineDiffView (linha 25) | `.font(.system(size: 12, weight: .medium))` | `.font(MacChromeTypography.captionStrong)` |

Adicionar `.tracking(MacChromeTypography.tracking(for: .body))` no fileName.

**Verify**: `make build` → exit 0; preview deve mostrar fontes ligeiramente diferentes

### Step 3: Substituir `.system(size:)` por `MacChromeTypography` em HistoryTimelineSectionView

| Localização | Antes | Depois |
|------------|-------|--------|
| section title (linha 49) | `.font(.system(size: 12, weight: .semibold))` | `.font(MacChromeTypography.sectionLabel)` |
| commit subject (linha 108) | `.font(.system(size: 13, weight: .medium))` | `.font(MacChromeTypography.body)` |
| "Future" badge (linha 114) | `.font(.system(size: 9, weight: .semibold))` | `.font(MacChromeTypography.captionStrong)` |
| chevron (linha 125) | `.font(.system(size: 10, weight: .semibold))` | `.font(MacChromeTypography.caption)` |

**Verify**: `make build` → exit 0

### Step 4: Substituir `.system(size:)` em CommitmentHoverCardView e CommitDetailPageView

**CommitHoverCardView:**
| Localização | Antes | Depois |
|------------|-------|--------|
| author initials (linha 35) | `.font(.system(size: 12, weight: .bold))` | `.font(.body.weight(.bold))` |
| author name (linha 43) | `.font(.system(size: 12, weight: .semibold))` | `.font(.subheadline.weight(.semibold))` |
| timestamp (linha 46) | `.font(.system(size: 10))` | `.font(.caption)` |
| subject (linha 58) | `.font(.system(size: 14, weight: .semibold))` | `.font(.headline.weight(.semibold))` |
| body (linha 67) | `.font(.system(size: 12))` | `.font(.subheadline)` |
| stats (linha 77) | `.font(.system(size: 11))` | `.font(.caption)` |
| short hash (linha 82) | `.font(.system(size: 11, weight: .semibold))` | `.font(.caption.weight(.semibold))` |

**CommitDetailPageView:**
| Localização | Antes | Depois |
|------------|-------|--------|
| "Back" text (linha 72) | `.font(.system(size: 12, weight: .medium))` | `.font(.subheadline.weight(.medium))` |
| "Commit Details" (linha 83) | `.font(.system(size: 12, weight: .semibold))` | `.font(.subheadline.weight(.semibold))` |
| author name (linha 96) | `.font(.system(size: 12, weight: .semibold))` | `.font(.subheadline.weight(.semibold))` |
| author email (linha 98) | `.font(.system(size: 11))` | `.font(.caption)` |
| timestamp (linha 103) | `.font(.system(size: 11))` | `.font(.caption)` |
| subject (linha 124) | `.font(.system(size: 15, weight: .semibold))` | `.font(.title2.weight(.semibold))` |
| body (linha 130) | `.font(.system(size: 12))` | `.font(.subheadline)` |
| stats (linha 140) | `.font(.system(size: 11))` | `.font(.caption)` |
| action links (linha 195) | `.font(.system(size: 11, weight: .medium))` | `.font(.caption.weight(.medium))` |
| "Changed Files" (linha 208) | `.font(.system(size: 12, weight: .semibold))` | `.font(.subheadline.weight(.semibold))` |

**Verify**: `make build` → exit 0

### Step 5: Substituir `.system(size:)` nos demais componentes

Percorrer os arquivos no escopo e substituir todos os `.font(.system(size:))`:
- `CommitComposer.swift` → hint/error labels
- `InlineStatusBannerView.swift` → caption, headline
- `MainMenuHeaderView.swift` → captionStrong (chevrão)
- `BottomBranchSelector.swift` → caption/monospacedCaption
- `MainMenuCommandPalette.swift` → body, caption, sectionLabel

**Verify**: `make build` → exit 0; `grep -rn '\.system(size:' GitMenuBar/Components/ GitMenuBar/Pages/` → 0 matches

### Step 6: Adicionar `.dynamicTypeSize` no container principal

Em `MainMenuView.swift`, adicionar no `VStack` raiz:

```swift
.dynamicTypeSize(...DynamicTypeSize.accessibility3)
```

Isso permite que o layout se ajuste até o maior tamanho de acessibilidade.

**Verify**: `make build` → exit 0; aumentar texto no System Settings > Displays > Text Size → ver app se adaptar

### Step 7: Adicionar `@ScaledMetric` para espaçamentos-chave

Em `MacChromeMetrics.swift`, adicionar scaled metrics para os espaçamentos
principais que devem escalar com o texto:

```swift
extension MacChromeMetrics {
    @ScaledMetric static var compactSpacingScaled: CGFloat = compactSpacing
    @ScaledMetric static var panelPaddingScaled: CGFloat = panelPadding
    @ScaledMetric static var windowPaddingScaled: CGFloat = windowPadding
}
```

Usar `compactSpacingScaled` em vez de `compactSpacing` nos lugares onde
o espaçamento está diretamente acoplado ao redor de texto.

**Verify**: `make build` → exit 0

## Test plan

- Todos os testes existentes devem continuar passando.
- O `grep` final garante que não sobrou `.system(size:)` nos diretórios de UI.
- Verificar visualmente cada preview com `.dynamicTypeSize(.accessibility3)`.

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make lint-changed` exits 0
- [ ] `grep -rn '\.system(size:' GitMenuBar/Components/ GitMenuBar/Pages/` → 0 matches
- [ ] `.tracking()` adicionado nos textos principais (títulos, body, captions)
- [ ] `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` presente no container principal
- [ ] `MacChromeTypography` tem helper `tracking(for:)`
- [ ] Nenhum arquivo fora do escopo foi modificado

## STOP conditions

- Se `make build` falhar, verificar se alguma substituição de `.system(size:)` quebrou
  a resolução de tipo; reportar se não conseguir corrigir em 2 tentativas.
- Se um preview ficar quebrado visualmente (texto cortado, layout desalinhado), reportar.
- Se os arquivos em "Current state" não corresponderem ao código vivo (drift), reportar.

## Maintenance notes

- **Regra**: nunca usar `.font(.system(size:))` em novos componentes — sempre usar
  `MacChromeTypography` ou `.font(.body.weight())` etc.
- Adicionar tracking sempre que usar um tamanho de fonte explícito.
- Para fontes monospaced, usar `.font(MacChromeTypography.monospacedCaption)`.
- Revisar `@ScaledMetric` quando novos layouts de texto forem adicionados.
