# Plan 008: Consolidate agent skill guidance into fewer stronger owners

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no; this plan is serial unless a named independent workstream is added during reclassification.
- **Reviewer required**: no; the scope does not require a separate review by default.
- **Rationale**: Mudança documental delimitada, mas ambígua por envolver roteamento e catálogo.
- **Escalate when**: Se incluir código de produto, configuração global, modelos ou novos executores.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report. Do not improvise. When done, update the status row for this plan in
> `plans/README.md`, unless a reviewer dispatched you and told you they maintain
> the index.
>
> **Drift check (run first)**:
>
> ```bash
> git diff --stat d072286..HEAD -- AGENTS.md README.md .agents plans/README.md
> ```
>
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts below against the live files before proceeding. If
> the excerpts no longer match the same responsibilities, stop and report the
> drift instead of applying this plan mechanically.

## Status

> Historical note: this plan was completed before the global Codex skill
> routing contract. Its local `improve` and `thermo` copies are superseded by
> `global:improve`, `global:thermo-nuclear-code-quality-review`, and the
> project-only profile declared in `AGENTS.md`.

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs / dx
- **Planned at**: commit `d072286`, 2026-07-10

## Why this matters

GitMenuBar's local agent skills currently split ordinary delivery guidance
across multiple small skills and split macOS UI guidance across implementation
and broad HIG guidance. That forces agents, especially lower-capacity models, to
load and reconcile overlapping instructions before they can act. This plan
consolidates those responsibilities into fewer canonical skills while keeping
specialist skills for menu-bar behavior, release packaging, testing, security,
performance, accessibility, concurrency, and Swift conventions.

The desired end state is smaller and easier to route:

- `delivery-workflow` owns build/test/lint routing, validation scope, merge
  gates, logs, git workflow evidence, and manual sign-off focus.
- `macos-app-engineering` owns ordinary SwiftUI/AppKit implementation plus
  macOS design acceptance rules.
- `menubar` stays separate because GitMenuBar is a menu-bar app and its
  `NSStatusItem` invariants are product-specific.
- `thermo-nuclear-code-quality-review` becomes the default strict code-review
  skill instead of referencing a missing `code-review` skill.

## Current state

Relevant files and their roles:

- `AGENTS.md` - top-level agent policy and primary skill list.
- `.agents/SKILLS_INDEX.md` - local skill registry and routing notes.
- `.agents/skills/quality-assurance/SKILL.md` - merge gate and verification
  scope guidance.
- `.agents/skills/build-macos-apps/SKILL.md` - command routing and log triage.
- `.agents/skills/macos-development/SKILL.md` - platform lifecycle and
  SwiftUI/AppKit bridge guidance.
- `.agents/skills/macos-design-guidelines/SKILL.md` - broad macOS HIG guidance.
- `.agents/skills/menubar/SKILL.md` - concise menu-bar app invariants.
- `.agents/skills/thermo-nuclear-code-quality-review/SKILL.md` - strict
  maintainability review guidance.
- `skills-lock.json` - tracks installed external skills; do not edit it unless
  this repo's skill installer actually changes external dependencies.

Current command and merge policy, from `AGENTS.md:17-35`:

```markdown
## Command Surface

- `make build`
- `make build-release`
- `make test`
- `make lint`
- `make lint-fix`
- `make dmg`
- `make clean`
- `make setup`

## Execution Policy

- Prefer CLI-first verification and reproducible commands.
- Keep changes small and validated incrementally.
- When working from a branch, PR, or local diff, inspect the touched files first and treat lint findings in modified code as mandatory work for the same change.
- Resolve critical lint violations in the diff before running full-project verification; do not defer issues introduced or exposed by the current change.
- Before merge, run: `make build && make test && make lint`.
```

Current primary skills, from `AGENTS.md:44-55`:

```markdown
## Skills

Use `.agents/SKILLS_INDEX.md` as the local skill registry.

Primary skills in this repo:

- `build-macos-apps`
- `quality-assurance`
- `macos-development`
- `menubar`
- `swift-conventions`
- `code-quality`
```

Current skill registry overlap, from `.agents/SKILLS_INDEX.md:9-14`:

```markdown
| `build-macos-apps`          | `.agents/skills/build-macos-apps/`          | Reproducing build, test, lint, or packaging failures and tracing them through local scripts/logs                        |
| `quality-assurance`         | `.agents/skills/quality-assurance/`         | Defining verification scope, merge gates, and manual checks for a change                                                |
| `release-management`        | `.agents/skills/release-management/`        | Preparing a release, validating DMGs, and checking release readiness                                                    |
| `macos-development`         | `.agents/skills/macos-development/`         | Working on SwiftUI/AppKit lifecycle, platform services, window ownership, and bridge boundaries                         |
| `menubar`                   | `.agents/skills/menubar/`                   | Changing `NSStatusItem`, popovers, app activation, and menu bar specific behavior                                       |
| `macos-design-guidelines`   | `.agents/skills/macos-design-guidelines/`   | Applying macOS HIG rules for menus, windows, keyboard, popovers, and accessibility                                      |
```

Current catalog notes explicitly keep the overlap separate, from
`.agents/SKILLS_INDEX.md:29-34`:

```markdown
- `build-macos-apps` is for reproduction and script routing; it is not the merge gate skill.
- `quality-assurance` owns verification depth and manual sign-off scope.
- `macos-development`, `menubar`, and `macos-design-guidelines` are intentionally separate:
  - `macos-development`: runtime and implementation mechanics
  - `menubar`: status item and popover invariants
  - `macos-design-guidelines`: HIG and desktop UX rules
```

Current QA skill is only verification scope and merge gate,
`.agents/skills/quality-assurance/SKILL.md:8-20`:

```markdown
Use this skill to decide how much verification is required for a change.

## Merge Gate

- Minimum before merge: `make build && make test && make lint`

## Scope Matrix

- Pure refactor with unchanged behavior: run the merge gate and target affected tests.
- Git logic, parsing, or persistence changed: add or update regression tests.
- Menu bar or window behavior changed: manually verify status item, activation, dismissal, and repo/branch actions.
- Credentials or AI provider flows changed: include secure-storage and migration checks.
- Packaging changed: run `make build-release`, `make dmg`, and validate the DMG manually.
```

Current build skill owns command routing and logs,
`.agents/skills/build-macos-apps/SKILL.md:10-22`:

```markdown
## Command Routing

- `make build`: Debug build through `scripts/run-build.sh`
- `make build-release`: Release build through `scripts/run-build.sh --configuration Release`
- `make test`: XCTest flow through `scripts/run-tests-xcode.sh`
- `make lint`: SwiftFormat + SwiftLint checks through `scripts/lint.sh`
- `make lint-fix`: auto-fix pass through `scripts/lint-fix.sh`
- `make dmg`: Release build plus DMG packaging through `scripts/create-dmg.sh`

## Log Locations

- Debug/Release build failures: `/tmp/gitmenubar-build-debug.log` or `/tmp/gitmenubar-build-release.log`
- Test failures: `/tmp/gitmenubar-test.log`
```

Current macOS implementation skill is concise,
`.agents/skills/macos-development/SKILL.md:8-23`:

```markdown
Use this skill when implementing platform behavior, not just visual polish.

## Focus Areas

- App lifecycle and activation policy
- Window, popover, and controller ownership
- SwiftUI to AppKit bridges
- Persistence of desktop-specific state
- Main-actor coordination for UI state

## Core Rules

- Keep platform state ownership explicit; one controller should own each window, popover, or status item lifecycle.
- Use AppKit only where SwiftUI is insufficient or less reliable.
- Cross the SwiftUI/AppKit boundary in a small adapter layer instead of leaking AppKit concerns across feature code.
- Persist desktop state only when it improves continuity and stays predictable across relaunches.
```

Current HIG skill is broad and generic, from
`.agents/skills/macos-design-guidelines/SKILL.md:1-22`:

```markdown
name: macos-design-guidelines
description: Apple Human Interface Guidelines for Mac. Use when building macOS apps with SwiftUI or AppKit, implementing menu bars, toolbars, window management, or keyboard shortcuts. Triggers on tasks involving Mac UI, desktop apps, or Mac Catalyst.

# macOS Human Interface Guidelines

Mac apps serve power users who expect deep keyboard control, persistent menu bars, resizable multi-window layouts, and tight system integration. These guidelines codify Apple's HIG into actionable rules with SwiftUI and AppKit examples.

## 1. Menu Bar (CRITICAL)

Every Mac app must have a menu bar. It is the primary discovery mechanism for commands. Users who cannot find a feature will look in the menu bar before anywhere else.

### Rule 1.1 -- Provide Standard Menus

Every app must include at minimum: **App**, **File**, **Edit**, **View**, **Window**, **Help**. Omit File only if the app is not document-based. Add app-specific menus between Edit and View or between View and Window.
```

This broad guidance is not wrong, but for GitMenuBar it overlaps with
`menubar`, `macos-development`, `accessibility-audit`, and `swift-conventions`.
The new skill should keep the actionable macOS acceptance criteria and drop the
long generic examples.

Current menu-bar skill should stay separate,
`.agents/skills/menubar/SKILL.md:8-18`:

```markdown
Use this skill for `NSStatusItem`, status item interaction, menu/popup opening, and app-style behavior that is unique to a menu bar app.

## Invariants

- Register the status item once and keep its lifetime explicit.
- Left-click, right-click, and modifier-click behavior must be intentional and documented in code.
- Opening the menu should not create duplicate controllers, duplicate work, or stale state.
- Dismissal must be predictable with outside click, focus changes, and `Esc` where applicable.
```

Current thermo review skill has stale routing,
`.agents/skills/thermo-nuclear-code-quality-review/SKILL.md:1-24`:

```markdown
name: thermo-nuclear-code-quality-review
description: Run an extremely strict maintainability review for abstraction quality, giant files, and spaghetti-condition growth. Use for a thermo-nuclear code quality review, thermonuclear review, deep code quality audit, or especially harsh maintainability review.
disable-model-invocation: true

## Scope Boundary

- This skill owns unusually strict code-quality review prompts and approval bars.
- This skill is the mandatory structural maintainability pass for every `../code-review/SKILL.md` review.
- It does not replace `../code-quality/SKILL.md` for everyday readability/refactoring guidance.
- It does not own semáforo review formatting; use `../code-review/SKILL.md` for the final findings format and severity framing.

Also use this skill whenever `../code-review/SKILL.md` is used. A normal "code review" in Prisma must include this structural pass.
```

There is no `.agents/skills/code-review/` in the current skill list. Leaving
this reference in place gives lower-capacity agents an impossible dependency.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| List skills | `find .agents/skills -maxdepth 2 -name SKILL.md -print \| sort` | Shows the final skill set and no deleted skill directories |
| Search stale routing | `rg -n "build-macos-apps|quality-assurance|macos-development|macos-design-guidelines|code-review|Prisma|disable-model-invocation" .agents AGENTS.md README.md` | No matches, except intentional historical notes if any are explicitly marked as history |
| Search new routing | `rg -n "delivery-workflow|macos-app-engineering|thermo-nuclear-code-quality-review" .agents AGENTS.md README.md` | Shows the new skill registry, primary skills, and cross-skill references |
| Whitespace check | `git diff --check` | exit 0 |
| Repo gate | `make build && make test && make lint` | exit 0 for all three commands |

The repo does not currently expose a `guidance-check` target. Do not invent one
inside this plan.

## Suggested executor toolkit

Use these local skills if available:

- `improve` only to read this plan or refine it. Do not use it to implement.
- `code-quality` to keep the skill set smaller without deleting useful
  specialist boundaries.
- `thermo-nuclear-code-quality-review` after the edits to review the guidance
  shape before final validation.

## Scope

**In scope**:

- `AGENTS.md`
- `.agents/SKILLS_INDEX.md`
- `.agents/skills/build-macos-apps/` (delete after migration)
- `.agents/skills/quality-assurance/` (delete after migration)
- `.agents/skills/macos-development/` (delete after migration)
- `.agents/skills/macos-design-guidelines/` (delete after migration)
- `.agents/skills/delivery-workflow/SKILL.md` (create)
- `.agents/skills/macos-app-engineering/SKILL.md` (create)
- `.agents/skills/thermo-nuclear-code-quality-review/SKILL.md`
- `README.md`, only if it references deleted skill names
- `plans/README.md`, only to mark this plan DONE when complete

**Out of scope**:

- Application Swift source files.
- Tests, Xcode project files, packaging scripts, and app resources.
- `skills-lock.json`, unless the skill installer changes external skill
  dependencies as part of a deliberate separate operation.
- External installed skills: `swift-concurrency`, `swift-testing-expert`, and
  `swiftui-performance-audit`.
- Specialist local skills that should stay separate:
  `menubar`, `release-management`, `test-strategy`, `security-credentials`,
  `performance-profiling`, `accessibility-audit`, `swift-conventions`,
  `code-quality`, and `improve`.
- A new general `debugging-diagnostics` skill. That may be useful later, but it
  is not required to remove the current high-confidence overlap.

## Git workflow

- Branch: `docs/consolidate-agent-skills`
- Use conventional commits. Suggested commit:
  `docs(agents): consolidate GitMenuBar skill guidance`
- Do not push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create `delivery-workflow`

Create `.agents/skills/delivery-workflow/SKILL.md`.

Use this frontmatter:

```markdown
---
name: delivery-workflow
description: Delivery, verification, command routing, git evidence, and merge-readiness workflow for GitMenuBar changes.
---
```

The body must include these sections:

1. `# Delivery Workflow`
2. `When to Use`
3. `Command Routing`
4. `Validation Scope`
5. `Triage Flow`
6. `Manual Sign-Off Focus`
7. `Git and Evidence`
8. `Boundaries`

Required content to migrate into this skill:

- All command routing from `build-macos-apps`:
  `make build`, `make build-release`, `make test`, `make lint`,
  `make lint-fix`, and `make dmg`, including the script each command calls.
- Log locations from `build-macos-apps`:
  `/tmp/gitmenubar-build-debug.log`,
  `/tmp/gitmenubar-build-release.log`, and `/tmp/gitmenubar-test.log`.
- The merge gate from `quality-assurance`:
  `make build && make test && make lint`.
- The QA scope matrix:
  pure refactor, Git logic/parsing/persistence, menu bar/window behavior,
  credentials/AI provider flows, and packaging.
- Manual sign-off focus:
  opening from menu bar, switching repositories, branch actions, commit flow,
  sync flow, settings/account panes when touched.
- Triage rule:
  reproduce with the narrowest `make` target first, inspect the owning script,
  read the generated log, surface the first actionable failure, then escalate.

Required boundaries:

- Say this skill owns delivery mechanics and merge readiness.
- Say release publication and DMG readiness beyond command routing belong to
  `release-management`.
- Say test design details belong to `test-strategy`.
- Say menu-bar lifecycle behavior belongs to `menubar`.
- Say code structure feedback belongs to `code-quality` and
  `thermo-nuclear-code-quality-review`.

Keep the file concise. Target 100-170 lines. Do not copy generic process prose
from Prisma or any other repo.

**Verify**:

```bash
test -f .agents/skills/delivery-workflow/SKILL.md
rg -n "make build|make build-release|make test|make lint|make dmg|/tmp/gitmenubar" .agents/skills/delivery-workflow/SKILL.md
```

Expected result: both commands exit 0 and the `rg` output shows the command
routing and log locations in the new skill.

### Step 2: Create `macos-app-engineering`

Create `.agents/skills/macos-app-engineering/SKILL.md`.

Use this frontmatter:

```markdown
---
name: macos-app-engineering
description: macOS SwiftUI/AppKit implementation and native design guidance for GitMenuBar UI, lifecycle, settings, previews, and platform behavior.
---
```

The body must include these sections:

1. `# macOS App Engineering`
2. `When to Use`
3. `Responsibilities`
4. `Platform Rules`
5. `Design Rules`
6. `Preview and Accessibility Expectations`
7. `Validation`
8. `Boundaries`

Required content to migrate from `macos-development`:

- App lifecycle and activation policy.
- Window, popover, and controller ownership.
- SwiftUI/AppKit bridge boundaries.
- Desktop state persistence.
- Main-actor coordination for UI state.
- "One controller should own each window, popover, or status item lifecycle."
- "Use AppKit only where SwiftUI is insufficient or less reliable."
- Keep SwiftUI/AppKit boundary in a small adapter layer.
- Validate lifecycle-sensitive changes by launching, opening, dismissing, and
  relaunching.

Required HIG/design content to retain from `macos-design-guidelines`, rewritten
for this repo instead of copied wholesale:

- Prefer native macOS controls and platform behaviors over custom chrome unless
  the custom UI is required by the menu-bar workflow.
- Keep command names, labels, and shortcuts stable.
- Use disabled states and contextual titles when actions are unavailable or
  state-dependent.
- Respect keyboard access, focus order, reduced motion, and VoiceOver routing.
- Keep windows/popovers resizable or size-constrained only when the content
  genuinely requires it.
- Do not paste long generic HIG code examples into the new skill.

Required boundaries:

- `menubar` remains the owner for `NSStatusItem`, status-item click behavior,
  popover/menu dismissal, and menu-bar app invariants.
- `accessibility-audit` remains the owner for deep VoiceOver, keyboard,
  contrast, focus, and reduced-motion reviews.
- `swift-conventions` remains the owner for Swift naming, type safety, lint
  shape, and required previews.
- `swiftui-performance-audit` remains the owner for SwiftUI invalidation,
  layout thrash, and profiling evidence.
- `delivery-workflow` remains the owner for build/test/lint routing and merge
  gates.

Keep the file concise. Target 120-220 lines.

**Verify**:

```bash
test -f .agents/skills/macos-app-engineering/SKILL.md
rg -n "NSStatusItem|menubar|accessibility-audit|swift-conventions|delivery-workflow|SwiftUI|AppKit" .agents/skills/macos-app-engineering/SKILL.md
```

Expected result: both commands exit 0 and the `rg` output shows the new skill
routes specialist work to the correct remaining skills.

### Step 3: Remove superseded skill directories

Delete these directories after their useful content has been migrated:

```text
.agents/skills/build-macos-apps/
.agents/skills/quality-assurance/
.agents/skills/macos-development/
.agents/skills/macos-design-guidelines/
```

Do not delete `menubar`.

**Verify**:

```bash
test ! -e .agents/skills/build-macos-apps
test ! -e .agents/skills/quality-assurance
test ! -e .agents/skills/macos-development
test ! -e .agents/skills/macos-design-guidelines
test -f .agents/skills/menubar/SKILL.md
```

Expected result: all commands exit 0.

### Step 4: Update top-level routing docs

Update `AGENTS.md`:

- In "Primary skills in this repo", replace:
  `build-macos-apps`, `quality-assurance`, and `macos-development`
  with:
  `delivery-workflow` and `macos-app-engineering`.
- Keep `menubar`, `swift-conventions`, and `code-quality`.
- Add `thermo-nuclear-code-quality-review` to the primary list if the list is
  meant to cover review work. If keeping the primary list intentionally short,
  mention in one line that strict code review uses
  `thermo-nuclear-code-quality-review`.

Update `.agents/SKILLS_INDEX.md`:

- Remove rows for the four deleted skills.
- Add rows for `delivery-workflow` and `macos-app-engineering`.
- Update catalog notes so they say:
  - `delivery-workflow` owns command routing, verification depth, merge gate,
    logs, git evidence, and manual sign-off.
  - `macos-app-engineering` owns ordinary SwiftUI/AppKit implementation and
    native design acceptance.
  - `menubar` remains separate because GitMenuBar's status item and popover
    behavior are product-critical.
  - `release-management` remains separate for release and DMG readiness.
  - external skills remain tracked in `skills-lock.json`.

Update `README.md` only if it references any deleted skill name.

**Verify**:

```bash
rg -n "build-macos-apps|quality-assurance|macos-development|macos-design-guidelines" AGENTS.md .agents/SKILLS_INDEX.md README.md
```

Expected result: no output. If a historical mention is intentionally retained,
it must say it is historical and must not be a routing instruction.

### Step 5: Make thermo review self-contained and default

Edit `.agents/skills/thermo-nuclear-code-quality-review/SKILL.md`.

Required changes:

- Remove the `disable-model-invocation: true` frontmatter line.
- Remove all references to `../code-review/SKILL.md`.
- Remove the Prisma-specific sentence.
- Make this the default GitMenuBar code-review skill for "review", "code
  review", "audit this PR", "deep review", and strict maintainability review.
- Add a compact output contract:
  findings first, ordered by severity, with file/line references; then open
  questions; then a short summary only if useful.
- Add severity labels:
  - `Critical`: breaks behavior, safety, data integrity, or merge readiness.
  - `Medium`: should fix before merge.
  - `Minor`: optional cleanup or style.
- Keep the existing strict structural checklist, but remove duplicate prose if
  the file becomes too long.

Do not weaken the skill's maintainability bar.

**Verify**:

```bash
rg -n "code-review|Prisma|disable-model-invocation" .agents/skills/thermo-nuclear-code-quality-review/SKILL.md
rg -n "Critical|Medium|Minor|findings first|code review" .agents/skills/thermo-nuclear-code-quality-review/SKILL.md
```

Expected result: the first command prints no output and exits 1 because there
are no matches. The second command prints matches and exits 0.

### Step 6: Search and fix stale cross-references

Run:

```bash
rg -n "build-macos-apps|quality-assurance|macos-development|macos-design-guidelines|code-review|Prisma|disable-model-invocation" .agents AGENTS.md README.md
```

Fix every operational stale reference. Historical references inside existing
plans may remain, but they must not be in `.agents`, `AGENTS.md`, or `README.md`.

If this command reports only historical matches under `plans/`, no change is
required for those old plans.

**Verify**:

```bash
rg -n "build-macos-apps|quality-assurance|macos-development|macos-design-guidelines|code-review|Prisma|disable-model-invocation" .agents AGENTS.md README.md
```

Expected result: no output.

### Step 7: Final validation and index update

Run:

```bash
find .agents/skills -maxdepth 2 -name SKILL.md -print | sort
git diff --check
make build && make test && make lint
```

Expected result:

- The skill list contains `delivery-workflow` and `macos-app-engineering`.
- The skill list does not contain `build-macos-apps`, `quality-assurance`,
  `macos-development`, or `macos-design-guidelines`.
- `git diff --check` exits 0.
- `make build`, `make test`, and `make lint` all exit 0.

After validation passes, update this plan's row in `plans/README.md` from TODO
to DONE.

## Test plan

This is a guidance-only change. Do not add or edit application tests.

Verification consists of:

- stale-reference searches proving deleted skill names no longer route active
  agent behavior,
- existence checks proving the new skill owners exist,
- `git diff --check`,
- and the repo merge gate `make build && make test && make lint`.

## Done criteria

All must hold:

- [ ] `.agents/skills/delivery-workflow/SKILL.md` exists and contains command
      routing, log locations, verification scope, merge gate, manual sign-off,
      and boundaries.
- [ ] `.agents/skills/macos-app-engineering/SKILL.md` exists and contains
      SwiftUI/AppKit lifecycle rules, native macOS design rules, preview and
      accessibility expectations, validation, and boundaries.
- [ ] The four superseded skill directories are deleted:
      `build-macos-apps`, `quality-assurance`, `macos-development`, and
      `macos-design-guidelines`.
- [ ] `AGENTS.md` and `.agents/SKILLS_INDEX.md` route active work through the
      new skill names.
- [ ] `thermo-nuclear-code-quality-review` no longer references missing
      `code-review`, Prisma, or `disable-model-invocation`.
- [ ] `rg -n "build-macos-apps|quality-assurance|macos-development|macos-design-guidelines|code-review|Prisma|disable-model-invocation" .agents AGENTS.md README.md`
      prints no output.
- [ ] `git diff --check` exits 0.
- [ ] `make build && make test && make lint` exits 0.
- [ ] `plans/README.md` marks Plan 008 DONE.

## STOP conditions

Stop and report back if:

- The drift check shows `.agents`, `AGENTS.md`, `README.md`, or
  `plans/README.md` changed after `d072286` and the current responsibilities no
  longer match this plan.
- You find another active routing document outside `.agents`, `AGENTS.md`, or
  `README.md` that is authoritative and conflicts with this plan.
- Removing the four superseded skills would also remove installed external
  skill metadata from `skills-lock.json`.
- Validation requires changing Swift source, tests, Xcode project files, or
  scripts.
- `make build && make test && make lint` fails twice for reasons that are not
  obviously unrelated to this docs-only change.

## Maintenance notes

- Future delivery-policy changes should update `delivery-workflow` first, then
  mirror only the shortest stable rule in `AGENTS.md`.
- Future ordinary macOS UI guidance should update `macos-app-engineering`;
  reserve `menubar` for status item and popover invariants.
- Do not reintroduce a separate build-only or QA-only skill unless the repo adds
  materially richer validation infrastructure, such as scoped checks or agent
  compact output targets.
- A future plan may add a general `debugging-diagnostics` skill if repeated bug
  investigations show overlap between performance profiling, logging, and
  failure triage. That is deliberately out of scope here.
