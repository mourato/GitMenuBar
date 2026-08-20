# Plan 073: Establish the commit/push and project-switch latency baseline

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the **STOP conditions** section occurs, stop and
> report — do not improvise. This plan adds measurement only; it must not alter
> Git behavior. When done, update the local status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat acad442..HEAD -- GitMenuBar/Services/Git/GitCommandRunner.swift GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBarTests/GitCommandRunnerTests.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift`
> If any in-scope file changed since this plan was written, compare the
> **Current state** excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none; Plan 057 is already DONE
- **Category**: perf
- **Planned at**: commit `acad442`, 2026-08-19
- **Finding ID**: `commit-push-project-switch-latency-baseline`
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: `main`; merge and push require explicit user authorization

## Execution profile

- **Recommended profile**: `implementer`
- **Risk/lane**: `Medium/Full`
- **Parallelizable**: no — the trace points must describe one coherent action
  and selection timeline
- **Reviewer required**: yes — the central Git runner must not expose command
  arguments, paths, credentials, or command output through diagnostics
- **Rationale**: The work is bounded, but it crosses the Git process boundary
  and the main-actor action/selection boundary. A normal implementer can add
  the instrumentation and run the repository gates without a broader rewrite.
- **Escalate when**: instrumentation needs a new persistence format, a public
  telemetry service, command output/argument logging, or changes to Git
  execution behavior.

## Why this matters

The current source shows that Git subprocesses run away from the main actor,
but it also shows that repository switching is rejected for the duration of the
whole primary action. Static inspection cannot tell us whether the user-visible
delay is mostly an ignored selection, repeated Git work, SwiftUI publication
churn, or a genuine main-thread stall. This plan adds bounded runtime evidence
so Plans 074 and 075 optimize the actual bottleneck instead of guessing.

## Current state

- `GitMenuBar/Services/Git/GitCommandRunner.swift:25-75` owns every synchronous
  `Process` launch. It waits for pipe output and process exit, but callers use
  it from `GitExecution.runOnBackground`.
- `GitMenuBar/Services/Git/GitExecution.swift:13-18` dispatches synchronous Git
  work to a global `.userInitiated` queue. Its command helper has no timing or
  command-count trace.
- `GitMenuBar/App/MainMenuActionCoordinator.swift:97-103` defines the current
  busy boundary:

  ```swift
  var isBusy: Bool {
      gitManager.isCommitting || aiCommitCoordinator.isGenerating || isExecutingPrimaryAction
  }

  var canSwitchRepository: Bool {
      !isBusy
  }
  ```

- `GitMenuBar/App/MainMenuActionCoordinator.swift:374-421` runs the commit,
  local refresh, remote-status check, push, second local refresh, and second
  remote-status check. The first and last phases need separate measurements.
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift:194-222` returns before
  selection when `canSwitchRepository` is false, then starts the selected
  refresh only after accepting a project.
- `GitMenuBarTests/MainMenuActionCoordinatorTests.swift:11-25` deliberately
  asserts that selection is blocked while an action is busy. This is a
  characterization test for the current behavior, not proof that the behavior
  is desirable.
- The project uses Swift 6 language mode, complete strict concurrency, and
  `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` in
  `GitMenuBar.xcodeproj/project.pbxproj:473-476`. New trace code must respect
  those boundaries and avoid unsafe global mutable state.

Existing `WindowOpenTrace` timing in `StatusBarController` measures window
presentation, not commit/push or sidebar selection. Do not conflate those
measurements.

## Commands and evidence

| Purpose | Command or procedure | Expected result |
|---|---|---|
| Drift | `git diff --stat acad442..HEAD -- GitMenuBar/Services/Git/GitCommandRunner.swift GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift GitMenuBarTests/GitCommandRunnerTests.swift GitMenuBarTests/MainMenuActionCoordinatorTests.swift` | Empty or understood drift only |
| Scoped feedback | `make agent-check` | Changed Swift lint and Debug build pass |
| Tests | `make test` | XCTest suite passes |
| Merge gate | `make lint && make test` | Both commands pass |
| Guidance | `make guidance-check` | Guidance validation passes |
| Hygiene | `git diff --check` | No whitespace errors |
| Runtime profiling | Xcode Instruments Swift Concurrency + Time Profiler templates on a real repository | Trace identifies main-thread time, task suspension, Git command count, and phase durations |

## Scope

**In scope (the only product/test files to modify):**

- `GitMenuBar/Services/Git/GitCommandRunner.swift`
- `GitMenuBar/App/MainMenuActionCoordinator.swift`
- `GitMenuBar/Pages/MainMenu/MainMenuActions.swift`
- `GitMenuBarTests/GitCommandRunnerTests.swift` (only for a pure redaction/label seam if needed)
- `GitMenuBarTests/MainMenuActionCoordinatorTests.swift` (only for trace lifecycle behavior if needed)
- `plans/README.md` status metadata after completion

**Out of scope:**

- Any change to commit, push, refresh, selection, or error semantics.
- A queue, actor, cache, debounce, scheduler, telemetry backend, or persisted
  performance database.
- Logging Git arguments, commit messages, file paths, remote URLs, command
  output, askpass values, environment variables, or credentials.
- UI layout, copy, animation, previews, or accessibility changes.
- Persisting traces in the repository. Runtime traces belong in the operator's
  local Instruments/log session or handoff, never in source control.

## Trace contract

Add the smallest native timing/signpost instrumentation that answers these
questions:

1. When did the primary commit/push action start, commit finish, remote-status
   check start/finish, push start/finish, and final action completion occur?
2. When did a project selection request arrive, get rejected by the busy guard,
   start a selected refresh, reach fast completion, and reach final completion?
3. How many Git child processes ran in each phase, and how long did each
   command family take?
4. Did the main actor spend meaningful time in the action or selection path, or
   did it only suspend while workers ran?

Use `os_signpost`/`OSLog` or the existing `CFAbsoluteTime` style. Identify a
command only by its Git subcommand (`status`, `diff`, `fetch`, `push`, `log`,
etc.) and identify an action with an opaque in-memory operation ID. Do not log
the complete `args` array: commit messages and file paths can be inside it.
Do not log the repository path; if correlation across repositories is needed,
use a short non-reversible in-memory label or separate operator runs.

Instrumentation must be disabled or effectively silent when the relevant log
level/signpost collection is not active. It must not keep an in-memory history,
retain command output, or change scheduling/QoS.

## Steps

### Step 1: Add command-family timing at the existing runner boundary

Wrap the existing `Process` lifetime in the Git runner with a signpost or
equivalent duration event. Use the first Git argument as the command family,
with a safe fallback for non-Git executables used by tests. Record success or
failure only as a boolean. Preserve the current pipe handling, askpass cleanup,
return type, and error text exactly.

If an explicit observer is needed for deterministic tests, keep it DEBUG-only,
optional, and limited to command family plus duration. Do not introduce a
`GitCommandRunner` protocol or change production dependency injection solely
for measurement.

**Verify**: `rg -n 'args|output|token|repositoryPath|os_signpost|Logger|signpost' GitMenuBar/Services/Git/GitCommandRunner.swift` shows that diagnostics do not emit command arguments, output, paths, or credentials; `make agent-check` passes.

### Step 2: Add action and selection phase markers

Instrument the existing primary-action and project-selection entry points. Add
markers around the existing phases without moving awaits or changing guards.
Keep the current rejected-selection behavior intact; the trace must make the
rejection visible rather than silently changing it.

Use the existing selected-refresh fast/final callbacks as the phase boundaries.
Do not add a second refresh callback, task, notification channel, or state
property visible to SwiftUI.

**Verify**: `rg -n 'commit|push|selection|fast|final|signpost|Logger' GitMenuBar/App/MainMenuActionCoordinator.swift GitMenuBar/Pages/MainMenu/MainMenuActions.swift` shows markers at existing boundaries only, and `make test` passes.

### Step 3: Capture a real baseline

Run the app under Instruments on at least:

- one small repository and one repository large enough to make refresh cost
  visible;
- a staged `Commit & Push` in project A followed immediately by a click on
  project B;
- a commit with no push, a push-only action, and a normal project switch;
- at least five repetitions per scenario, recording p50/p95 where practical.

Record outside the repository:

- time from project-B click to accepted selection;
- time to B fast refresh and final refresh;
- time spent waiting on A's push/fetch/history;
- child-process counts by phase;
- main-thread and SwiftUI rendering time;
- peak concurrent Git process count.

The expected current baseline is that a switch during the action emits a
rejected-selection event, while Git work continues off the main actor. If the
trace instead shows a main-thread stall, route the finding to a focused
SwiftUI/main-actor performance plan before implementing Plan 075.

**Verify**: the handoff contains the measured scenarios and timestamps, with
no copied command output, paths, credentials, or runtime state.

### Step 4: Hand off the decision gate

Compare the baseline with the repository budgets: menu/window response under
150 ms, fast refresh under 500 ms, and no more than one active Git operation
per repository unless a later plan explicitly proves safe overlap.

If repeated refresh/fetch work dominates, proceed to Plan 074. If the main
actor/render path dominates, stop and report the evidence; do not broaden this
plan into a SwiftUI rewrite. If the ignored selection is the only issue and
the action is already within budget, Plan 075 may be reduced to path-safe
selection state without a general queue.

**Verify**: `git diff --check` passes and the plan row is updated with the
measurement handoff, not a claimed runtime result that was not captured.

## Test plan

- Preserve the existing `GitCommandRunnerTests` askpass test and assert that
  the new diagnostic path does not expose the token.
- Preserve the existing action coordinator tests, including the current busy
  selection characterization until Plan 075 intentionally changes it.
- No timing-based unit tests, sleeps, real network calls, or persisted trace
  fixtures are allowed in this plan.
- Verification: `make agent-check`, `make test`, and `make lint && make test`.

## Done criteria

- [ ] Runtime markers identify action, selection, fast-refresh, final-refresh,
      and Git command-family durations.
- [ ] Diagnostics never include Git arguments, output, paths, remote URLs,
      tokens, or environment values.
- [ ] No production behavior or scheduling semantics changed.
- [ ] A real-repository baseline is recorded outside the repository.
- [ ] `make agent-check`, `make test`, `make lint && make test`,
      `make guidance-check`, and `git diff --check` pass.
- [ ] Only the in-scope files are modified, apart from the plan index.

## STOP conditions

Stop and report if:

- the drift check finds an unreviewed change in an in-scope file;
- a trace would require logging arguments, output, paths, credentials, or
  environment values;
- instrumentation changes command ordering, task priority, cancellation, or
  published state;
- a test requires sleeps, network access, or a persistent trace artifact;
- Instruments shows the main actor/render path is the dominant bottleneck and
  the proposed next step would be a SwiftUI redesign;
- any verification command fails twice after a reasonable scoped fix.

## Maintenance notes

- Keep the trace at the existing `GitCommandRunner` and action boundaries so
  future Git flows inherit measurement without a new telemetry abstraction.
- Remove or reduce the instrumentation after Plans 074–075 establish stable
  budgets unless a durable diagnostic is explicitly requested.
- The next executor must consume the measured evidence; it must not assume the
  nominal process count or network latency is the production bottleneck.
