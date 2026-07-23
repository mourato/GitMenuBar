# Plan 021: Adopt global macOS skill cores with a GitMenuBar overlay

Status: DONE — merged to `main` as `61dff55` via PR #1.
Priority: P1
Effort: M
Risk: MEDIUM
Depends on: global `/Users/usuario/.agents/plans/004-globalize-macos-skills-and-overlay-contract.md` merged to the configured global source of truth
Planned at commit: `aa6ef8a`
Planned on: 2026-07-23

## Execution profile

- **Recommended profile**: implementer + reviewer.
- **Risk/lane**: Medium/Full. This is a guidance migration with precedence and
  delivery implications; it must preserve GitMenuBar-specific invariants.
- **Parallelizable**: no — do not parallelize within this repository. Execute after the
  global contract is merged and serialize the five product migrations unless a
  maintainer explicitly assigns separate isolated worktrees.
- **Reviewer required**: yes — before merge. The reviewer must inspect the resulting
  discovery paths and confirm that no same-name local skill shadows a global
  core accidentally.
- **Rationale**: This guidance migration changes skill discovery and precedence
  while preserving GitMenuBar-specific invariants and specialist skills.
- **Escalate when**: the global overlay contract is absent or ambiguous, an
  unrelated change appears, or a requested deletion would remove product
  guidance.

## Why this plan exists

GitMenuBar has seven skills whose names and intent are shared by the other
macOS app repositories: `accessibility-audit`, `apple-design`, `code-quality`,
`delivery-workflow`, `macos-app-engineering`, `menubar`, and
`swift-conventions`. Keeping seven independently copied versions creates drift
and makes improvements expensive to propagate. The project also has valuable
local skills and references that must remain local, especially Git-specific
workflow, performance profiling, release, security, concurrency, and test
strategy guidance.

The target is a portable global core plus an explicit GitMenuBar overlay. The
overlay supplies product facts and exceptions; it is not a second generic
skill implementation.

## Current state and constraints

- The current branch is `main` at `aa6ef8a`; preserve unrelated work if the
  branch changes before execution.
- `AGENTS.md` already routes global `improve` and thermo review skills and
  requires `make guidance-check` after guidance changes.
- The repository exposes the merge gates `make guidance-check`, then
  `make lint && make test`.
- Seven local skill directories duplicate the proposed global macOS cores.
- Keep local specialist skills such as `benchmarking`,
  `performance-profiling`, `release-management`, `security-credentials`,
  `swift-concurrency`, `swift-testing-expert`, `swiftui-performance-audit`,
  and `test-strategy`.
- Preserve the GitMenuBar-specific motion reference currently under the local
  Apple Design skill by relocating it under the overlay before removing the
  duplicate skill directory.

## Scope

### In scope

- Update `AGENTS.md` with the explicit global-core/overlay contract and the
  GitMenuBar precedence rules.
- Update `.agents/review-profiles/thermo-gitmenubar.md` so product review
  routing uses the global cores and GitMenuBar overlays.
- Add `.agents/overlays/` with seven project overlay documents named after the
  global skill they customize. Each overlay must declare its project identity,
  parent global skill, and local precedence.
- Move the GitMenuBar-specific Apple Design motion reference to an
  overlay-owned reference path, and link it from the `apple-design` overlay.
- Remove only the seven duplicated generic local skill directories after their
  unique GitMenuBar facts and references have been preserved.
- Add this plan to `plans/README.md` and record the dependency on the global
  plan.
- Extend `scripts/validate-agent-guidance.sh` to enforce overlay metadata,
  positive global-core/overlay route pairs, no-shadow routing, stale-path
  absence, overlay link resolution, and a negative swapped-overlay check.

### Out of scope

- Swift source, Xcode project settings, assets, tests, or runtime behavior.
- Removing specialist local skills or changing their names.
- Provider-specific model/runtime configuration.
- Blindly concatenating global and local `SKILL.md` files.
- Deleting any branch, worktree, or remote ref that contains unrelated or
  unmerged work.

## Overlay content contract

Each of the seven overlay documents should contain only information that is
specific to GitMenuBar, including where relevant:

- product terminology, repository paths, and the menu-bar interaction model;
- GitMenuBar's build, lint, test, and guidance-check commands;
- status-item ownership, popover dismissal, latency, and preview invariants;
- accessibility and motion expectations, including the relocated motion
  reference;
- Git-specific branch/worktree/cleanup constraints where delivery guidance
  needs local context.

The overlays must not repeat generic Swift, AppKit, accessibility, testing, or
delivery rules that belong in the global cores. Do not create local directories
with the same skill names as the global cores after migration; the project
overlay must be the only local customization layer.

## Implementation steps

1. Re-read the global Plan 004 and verify that its seven global skill paths and
   overlay metadata contract are present in the merged global checkout. Stop
   if the global contract is absent or its precedence semantics changed.
2. Check the repository state with `git status --short --branch` and preserve
   any changes that appeared after this plan was authored. Do not start in a
   dirty worktree containing unrelated edits.
3. Inventory the seven local skills and their references. Extract only
   GitMenuBar-specific material into `.agents/overlays/`; relocate the motion
   reference without losing history or content.
4. Update `AGENTS.md` so an agent loads the global core first, then the matching
   GitMenuBar overlay, then specialist local skills. State that same-name local
   skill copies are forbidden and that overlay rules win only for project
   facts/exceptions.
5. Add the seven overlay documents with stable metadata and concise links to
   the global parent skill. Keep provider/runtime settings out of them.
6. Remove the seven duplicate generic skill directories, retaining all
   specialist skills and the relocated overlay reference.
7. Update the review profile and guidance validator so future routing changes
   cannot silently point at deleted generic skills.
8. Update `plans/README.md` with Plan 021's status, dependency, and the
   explicit commit → push → merge → cleanup delivery sequence.
9. Run the verification commands below. Have the reviewer inspect the diff,
   especially deleted files, overlay references, and `AGENTS.md` precedence.

## Verification and test plan

Run from `/Users/usuario/Documents/Projects/gitmenubar`:

```sh
git diff --check
make guidance-check
make lint
make test
```

Also verify structurally:

```sh
test -d .agents/overlays
test ! -d .agents/skills/accessibility-audit
test ! -d .agents/skills/apple-design
test ! -d .agents/skills/code-quality
test ! -d .agents/skills/delivery-workflow
test ! -d .agents/skills/macos-app-engineering
test ! -d .agents/skills/menubar
test ! -d .agents/skills/swift-conventions
for skill in accessibility-audit apple-design code-quality delivery-workflow macos-app-engineering menubar swift-conventions; do
  test -f ".agents/overlays/$skill.md"
  rg -q "^kind: project-overlay$" ".agents/overlays/$skill.md"
  rg -q "^extends: $skill$" ".agents/overlays/$skill.md"
  rg -q '^project: GitMenuBar$' ".agents/overlays/$skill.md"
  rg -q '^precedence: project$' ".agents/overlays/$skill.md"
done
rg -n "global|overlay|GitMenuBar|make guidance-check" AGENTS.md .agents/overlays .agents/review-profiles
make guidance-check
```

The guidance validator also mutates an isolated temporary AGENTS fixture with
one overlay route swapped and must reject that fixture.

`make lint && make test` is a merge gate even though the change is guidance-
only: the repository policy requires the normal project gate before delivery.
If either command fails for a pre-existing reason, record the exact failure,
do not weaken the gate, and stop before push.

## Git delivery and cleanup

The implementer must use an isolated worktree or otherwise confirm a clean,
single-purpose branch before editing. Do not commit unrelated changes.

```sh
git switch -c chore/gitmenubar-global-skill-overlays
git add AGENTS.md .agents/overlays .agents/skills plans/README.md plans/021-adopt-global-macos-skill-overlays.md
git diff --cached --check
git commit -m "docs(agents): adopt global macos skill overlays"
git push -u origin chore/gitmenubar-global-skill-overlays
```

Open a pull request, obtain the required review, and merge it through the
repository's protected-branch process. After the merge:

```sh
git switch main
git pull --ff-only origin main
git fetch --prune origin
git worktree list
git branch --merged main
git branch -d chore/gitmenubar-global-skill-overlays
git push origin --delete chore/gitmenubar-global-skill-overlays
git fetch --prune origin
```

Delete the local branch only after it is merged and no worktree uses it.
Delete the remote branch only after confirming the PR is merged and no remote
automation still needs it. Remove an isolated temporary worktree only after
its final diff is empty and its changes are represented in the merged commit.
Never delete `main`, an unmerged branch, or a worktree containing unrelated
work.

## Done criteria

- The seven generic cores are sourced globally and the seven GitMenuBar
  overlays are discoverable without same-name local shadow copies.
- GitMenuBar-specific motion guidance and all specialist skills are preserved.
- `AGENTS.md` explains loading order, precedence, and the no-copy rule.
- The GitMenuBar review profile routes through global cores and overlays.
- `scripts/validate-agent-guidance.sh` checks overlay metadata, no-shadow
  routing, positive global-core/overlay pairs, stale deleted-skill paths,
  overlay links, and swapped-overlay negative coverage.
- `make guidance-check`, `make lint`, `make test`, and `git diff --check` pass.
- The reviewed commit is pushed, merged, and the merged branch/worktree
  cleanup is complete locally and remotely.
- `plans/README.md` records the final status and commit/PR reference.

## STOP conditions

- The global Plan 004 is not merged or its overlay contract is ambiguous.
- The worktree contains unrelated or unmerged changes that cannot be isolated.
- A proposed deletion would remove GitMenuBar-specific guidance or a needed
  reference.
- `make guidance-check`, `make lint`, or `make test` fails without an approved
  pre-existing-failure record.
- The PR is not approved/merged; do not delete branches or worktrees.

## Maintenance notes

Future generic improvements belong in the global core and should be validated
against all five macOS repositories. GitMenuBar-specific exceptions belong in
the overlay or a clearly named specialist local skill, never in a copied global
skill. Re-run `make guidance-check` whenever `AGENTS.md`, overlay metadata, or
skill routing changes.
