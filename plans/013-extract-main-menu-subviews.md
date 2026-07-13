# Plan 013: Extrair sub-views focais da MainMenuView

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `High/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: yes; the plan has high-risk architectural, operational, or integration impact.
- **Rationale**: Extração arquitetural de uma superfície central e sensível do menu bar.
- **Escalate when**: Se alterar ownership do status item, popover, navegação ou contratos de estado.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat abdb924..HEAD -- GitMenuBar/Pages/MainMenu/ GitMenuBar/Components/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 009 (recomendado — evita conflitos de merge nas animações)
- **Category**: tech-debt
- **Planned at**: commit `abdb924`, 2026-07-10

## Why this matters

`MainMenuView` tem **60+ variáveis `@State`** e seu corpo principal é uma
única struct SwiftUI que gerencia estado de working tree, history, navigation,
command palette, branch operations, merge workflows, e muito mais. O padrão de
overlays em corrente (`applyX(to:) → applyY(to:)`) em `MainMenuOverlays.swift`
dificulta rastrear o que está visível. Mais de 20 `.onChange` handlers no mesmo
nível.

Isso torna qualquer mudança arriscada: efeitos colaterais imprevisíveis, previews
difíceis de isolar, e onboard lento para novos contribuidores. Extrair sub-views
focais com seu próprio estado reduz o raio de impacto e segue o princípio Apple
de **Simplicidade**: "Remova o desnecessário para que o propósito central brilhe."

## Current state

- `MainMenuView.swift` (336 linhas) + `MainMenuContent.swift` (431 linhas) +
  `MainMenuOverlays.swift` (394 linhas) + `MainMenuActions.swift` + `MainMenuComputed.swift` +
  `MainMenuMergeOverlays.swift` + `MainMenuMergeActions.swift` + `MainMenuRepositoryOptions.swift` —
  cerca de 2000+ linhas de extensões de uma única struct.

- `MainMenuView` declara ~60 `@State` no topo (linhas 9-94 de
  `MainMenuView.swift`). Exemplos:
  - `showDeleteConfirmation`, `isDeleting`, `deleteError` (delete repo)
  - `showMergeConfirmation`, `mergeBranchName`, `mergeTargetBranch` (merge)
  - `showDirtySwitchConfirmation`, `pendingSwitchBranch` (dirty switch)
  - `showBranchDeleteConfirmation`, `branchNameToDelete` (delete branch)
  - `showDiscardConfirmation`, `discardFilePath`, `discardFileStatus` (discard)
  - `showRestartConfirmation`, `restartError` (restart)
  - etc.

- `MainMenuOverlays.swift` aplica overlays em cadeia:
  ```swift
  func applyMainViewOverlays<Content: View>(to view: Content) -> some View {
      let commitAndRewriteOverlays = applyWhitespaceAndRewriteOverlays(to: view)
      let confirmationAlerts = applyConfirmationAlerts(to: commitAndRewriteOverlays)
      let sheets = applySheets(to: confirmationAlerts)
      return applyCommandPaletteOverlay(to: sheets)
  }
  ```

- `MainMenuContent.swift` tem toda a lógica de layout das seções staged, unstaged,
  history inline com closures que referenciam `self` (estado da view mãe).

**Convenções do repositório:**
- SwiftUI com `@EnvironmentObject` para dependências
- Extensions da view principal para organizar lógica
- Previews em todos os componentes
- `MacChromeMetrics`, `MacChromeTypography`, `MacChromePalette` para design tokens

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `make build`             | exit 0              |
| Tests     | `make test`              | exit 0, all pass    |
| Lint      | `make lint-changed`      | exit 0              |

## Scope

**In scope:**
- `GitMenuBar/Pages/MainMenu/MainMenuView.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuContent.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuOverlays.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuComputed.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuKeyboardNavigation.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuInteractionModels.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuMergeOverlays.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuMergeActions.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuRepositoryOptions.swift`
- (Criação de novos arquivos quando necessário)

**Out of scope:**
- `MainMenuCommandPalette.swift` e `MainMenuCommandPaletteResolver.swift` (já são isolados)
- `MainMenuPreviewHarness.swift`
- `StatusBarController.swift` e demais App/ arquivos
- Modelos e serviços
- Mudança de comportamento funcional

## Steps

### Step 1: Extrair `WorkingTreeSectionView`

Criar `Pages/MainMenu/WorkingTreeSectionView.swift` com:

```swift
struct WorkingTreeSectionView: View {
    let title: String
    let summary: WorkingTreeSectionSummary
    let files: [WorkingTreeFileRowAdapter]
    @Binding var isCollapsed: Bool
    let selectedItemID: MainMenuSelectableItem?
    let onSelect: (MainMenuSelectableItem) -> Void
    let onStageToggle: (String) -> Void
    let onOpen: (String) -> Void
    let onDiscard: (String, WorkingTreeFileStatus) -> Void
    let onReveal: (String) -> Void
    let onAction: () -> Void
    let onDiscardAll: (() -> Void)?
    let actionIcon: String
    let actionHelp: String

    // Estado interno
    @State private var discardFilePath: String?
    @State private var discardFileStatus: WorkingTreeFileStatus?
    @State private var showDiscardConfirmation = false

    // ... corpo movido de MainMenuContent.stagedSection e .unstagedSection
}
```

Mover o conteúdo de `stagedSection` e `unstagedSection` de `MainMenuContent.swift`
para esta nova view. A lógica de discard confirmation (que hoje está em
`MainMenuView`) deve ser movida para cá também.

Em `MainMenuContent.swift`, substituir as duas seções por:

```swift
WorkingTreeSectionView(
    title: "Staged",
    summary: stagedSummary,
    files: stagedRowAdapters,
    isCollapsed: $isStagedSectionCollapsed,
    selectedItemID: selectedMainItemID,
    onSelect: { selectMainItem($0) },
    onStageToggle: { unstageFile(path: $0) },
    onOpen: { gitManager.openFile(path: $0) },
    onDiscard: { path, status in
        discardFilePath = path
        discardFileStatus = status
        showDiscardConfirmation = true
    },
    onReveal: { gitManager.revealInFinder(path: $0) },
    onAction: unstageAllFiles,
    onDiscardAll: nil,
    actionIcon: "minus.circle",
    actionHelp: "Unstage all files"
)
```

**Verify**: `make build` → exit 0

### Step 2: Extrair `HistorySectionView`

Criar `Pages/MainMenu/HistorySectionView.swift` com:

```swift
struct HistorySectionView: View {
    let sections: [HistoryTimelineSectionModel]
    let selectedItemID: MainMenuSelectableItem?
    let isLoading: Bool
    let canLoadMore: Bool
    let onSelectRow: (HistoryRowAdapter) -> Void
    let onActivateCommit: (HistoryRowAdapter) -> Void
    let onRestoreCommit: (HistoryRowAdapter) -> Void
    let onEditCommitMessage: (HistoryRowAdapter) -> Void
    let onGenerateCommitMessage: (HistoryRowAdapter) -> Void
    let onLoadMore: () -> Void

    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HistorySectionHeaderView(
                commitCount: sections.flatMap(\.rows).count,
                isCollapsed: $isCollapsed
            )
            if !isCollapsed {
                // conteúdo movido de MainMenuContent.historySection
            }
        }
    }
}
```

Mover o conteúdo de `historySection` de `MainMenuContent.swift` para esta view.

**Verify**: `make build` → exit 0

### Step 3: Extrair `BranchManagementControlsView`

Criar `Pages/MainMenu/BranchManagementControlsView.swift` com a lógica do footer
de `MainMenuContent.swift`:

```swift
struct BranchManagementControlsView: View {
    let currentBranch: String
    let canShowAtomicCommits: Bool
    let onBranchTap: () -> Void
    let onAtomicCommits: () -> Void
    let onManage: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            BottomBranchSelectorView(
                currentBranch: currentBranch,
                // ... props
            )
            Spacer()
            // botões Atomic Commits, Manage, Settings
        }
    }
}
```

**Verify**: `make build` → exit 0

### Step 4: Extrair `ConfirmationDialogsView`

Criar `Pages/MainMenu/ConfirmationDialogsView.swift` com todos os `.alert` e
`.confirmationDialog` que hoje estão espalhados por `MainMenuOverlays.swift` e
`MainMenuMergeOverlays.swift`.

Cada alerta vira um método ou subview:

```swift
struct ConfirmationDialogsView: ViewModifier {
    // Bindings para cada diálogo
    @Binding var showDeleteConfirmation: Bool
    @Binding var showDiscardConfirmation: Bool
    @Binding var showMergeConfirmation: Bool
    // ... etc

    func body(content: Content) -> some View {
        content
            .alert("Delete Repository?", isPresented: $showDeleteConfirmation) { ... }
            .alert("Discard Changes?", isPresented: $showDiscardConfirmation) { ... }
            // ... cada alerta
    }
}
```

Ou simplesmente manter como extension de `MainMenuView` mas mover os closures
de ação para dentro de cada método em vez de referenciar `self` da view mãe.

**Abordagem recomendada**: Manter os alerts como ViewModifier para não perder
a capacidade de binding direto. Cada alerta é uma função em `MainMenuView` que
retorna `.alert(...)`.

**Verify**: `make build` → exit 0

### Step 5: Extrair `CommitWorkflowView`

Criar `Pages/MainMenu/CommitWorkflowView.swift` encapsulando o commit composer
e a lógica de whitespace/rewrite confirmation:

```swift
struct CommitWorkflowView: View {
    @Binding var commentText: String
    @FocusState.Binding var isCommentFieldFocused: Bool
    let showsCommentField: Bool
    let primaryButtonSystemImage: String?
    let isPrimaryActionBusy: Bool
    // ... props do CommitComposerSectionView

    // Estados internos de whitespace/rewrite
    @State private var showWhitespaceConfirmation = false

    var body: some View {
        CommitComposerSectionView(...)
            .confirmationDialog("Commit message contains only spaces", ...) { ... }
    }
}
```

**Verify**: `make build` → exit 0

### Step 6: Limpar `MainMenuView`

Após as extrações, `MainMenuView` deve ter drasticamente menos `@State`.
Remover variáveis que agora são gerenciadas internamente pelas sub-views:

- `showDiscardConfirmation`, `discardFilePath`, `discardFileStatus` → movido para `WorkingTreeSectionView`
- `showMergeConfirmation`, `mergeBranchName`, `mergeTargetBranch` → movido para `ConfirmationDialogsView`
- `showDirtySwitchConfirmation`, `pendingSwitchBranch` → movido para `ConfirmationDialogsView`
- `showBranchDeleteConfirmation`, `branchNameToDelete` → movido para `ConfirmationDialogsView`
- `showRestartConfirmation`, `restartError` → movido para `ConfirmationDialogsView`

O body principal deve ficar mais enxuto:

```swift
var body: some View {
    VStack(spacing: 10) {
        switch presentationModel.route {
        case .main:
            mainView
                .adaptiveMotion()
        case .createRepo(let path):
            CreateRepositoryPageView(...)
        case .historyDetail(let commitID):
            CommitDetailPageView(...)
        }
    }
    .alert("Delete Repository?", ...) { ... } // só os alerts que realmente ficam no topo
    .sheet(...) { ... } // sheets que ficam no topo
}
```

**Verify**: `make build` → exit 0; `make test` → all pass

### Step 7: Adicionar previews para cada nova sub-view

Cada sub-view extraída deve ter pelo menos um `#Preview` com dados mockados,
seguindo a política de previews do repo (AGENTS.md: "Any new Swift file that
renders interface must include at least one #Preview").

**Verify**: `grep -rn '#Preview' GitMenuBar/Pages/MainMenu/WorkingTreeSectionView.swift` → match
`grep -rn '#Preview' GitMenuBar/Pages/MainMenu/HistorySectionView.swift` → match (etc.)

## Test plan

- **Não** escrever novos testes de UI — esta é uma refatoração puramente
  estrutural que não muda comportamento.
- Executar `make test` para garantir que nenhum teste existente quebrou.
- O `make lint-changed` deve passar sem erros.
- Executar o app e verificar manualmente: commit, stage/unstage, history,
  branch switch, merge, delete, create branch — tudo funcional.

## Done criteria

- [ ] `make build` exits 0
- [ ] `make test` exits 0
- [ ] `make lint-changed` exits 0
- [ ] `MainMenuView` tem menos de 30 `@State` (vs ~60 antes)
- [ ] `WorkingTreeSectionView.swift` existe com preview
- [ ] `HistorySectionView.swift` existe com preview
- [ ] `BranchManagementControlsView.swift` existe com preview
- [ ] `ConfirmationDialogsView.swift` ou equivalente existe
- [ ] `CommitWorkflowView.swift` existe com preview
- [ ] Nenhum arquivo fora do escopo foi modificado
- [ ] Nenhum preview existente quebrou
- [ ] Todos os fluxos funcionais (commit, stage, branch, merge) continuam operacionais

## STOP conditions

- Se `make test` falhar, verificar se a extração moveu alguma lógica de副作用
  (side effect) junto com o estado. Reportar se não conseguir corrigir em 2 tentativas.
- Se o comportamento de algum fluxo mudar (ex: alerta não aparece, ação não
  executa), isso indica que um closure ou binding foi quebrado na extração —
  reportar imediatamente.
- Se os arquivos em "Current state" não corresponderem ao código vivo (drift), reportar.

## Maintenance notes

- **Nenhum novo `@State` deve ser adicionado em `MainMenuView`**. Novos estados
  pertencem às sub-views especializadas.
- A regra para saber se um estado pertence a uma sub-view: "este estado influencia
  apenas esta seção da UI?" Se sim, ele vive na sub-view, não no pai.
- O padrão de `@Binding` para comunicação pai-filho é preferível a
  `@EnvironmentObject` para estados locais de UI.
- Futuras refatorações podem extrair `BranchSelectorSectionView`,
  `RepositoryOptionsSectionView`, etc.
