# Skills Index

Skill registry for GitMenuBar.

The catalog is organized by responsibility so agents can trigger the narrowest useful skill instead of loading overlapping guidance.

| Skill                       | Location                                    | Use When                                                                                                                |
| --------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `delivery-workflow`         | `.agents/skills/delivery-workflow/`         | Command routing, verification scope, merge gate, logs, git evidence, and manual sign-off for a change                   |
| `macos-app-engineering`     | `.agents/skills/macos-app-engineering/`     | Ordinary SwiftUI/AppKit implementation and native macOS design acceptance for GitMenuBar UI                             |
| `menubar`                   | `.agents/skills/menubar/`                   | Changing `NSStatusItem`, popovers, app activation, and menu bar specific behavior                                       |
| `release-management`        | `.agents/skills/release-management/`        | Preparing a release, validating DMGs, and checking release readiness                                                    |
| `swift-conventions`         | `.agents/skills/swift-conventions/`         | Enforcing local Swift style, previews, naming, and safe structure in diffs                                              |
| `swift-concurrency`         | `.agents/skills/swift-concurrency/`         | Diagnosing data races, actor isolation, `Sendable` issues, async/await refactors, and Swift 6 migration                 |
| `benchmarking`              | `.agents/skills/benchmarking/`              | Latency budgets, metric collection, regression detection, and performance gate automation for Git operations and UI     |
| `code-quality`              | `.agents/skills/code-quality/`              | Refactors, deduplication, removal of dead code, and keeping architecture coherent                                       |
| `performance-profiling`     | `.agents/skills/performance-profiling/`     | Investigating startup cost, menu latency, rendering churn, memory growth, and expensive Git operations                  |
| `security-credentials`      | `.agents/skills/security-credentials/`      | Handling GitHub tokens, AI API keys, keychain access, migrations, and sensitive logging concerns                        |
| `accessibility-audit`       | `.agents/skills/accessibility-audit/`       | Reviewing keyboard access, VoiceOver, focus order, contrast, and reduced-motion behavior                                |
| `test-strategy`             | `.agents/skills/test-strategy/`             | Designing XCTest coverage, async tests, seams, doubles, and regression-oriented test plans                              |
| `swift-testing-expert`      | `.agents/skills/swift-testing-expert/`      | Using modern Swift Testing APIs, `#expect`/`#require`, traits, parameterized tests, async waiting, and XCTest migration |
| `swiftui-performance-audit` | `.agents/skills/swiftui-performance-audit/` | Auditing SwiftUI runtime performance, view invalidation, layout thrash, and when to request Instruments evidence        |
| `global:thermo-nuclear-code-quality-review` | `/Users/usuario/.codex/skills/thermo-nuclear-code-quality-review/` | Strict reviews, PR audits, pre-merge quality, and generic maintainability findings |
| `thermo-gitmenubar-profile` | `.agents/review-profiles/thermo-gitmenubar.md` | Project-only review invariants layered on the global thermo review |
| `global:improve`            | `/Users/usuario/.codex/skills/improve/` | Read-only audits and self-contained implementation plans |

## Catalog Notes

- `delivery-workflow` owns command routing, verification depth, merge gate, logs, git evidence, and manual sign-off.
- `macos-app-engineering` owns ordinary SwiftUI/AppKit implementation and native design acceptance.
- `menubar` remains separate because GitMenuBar's status item and popover behavior are product-critical.
- `release-management` remains separate for release and DMG readiness.
- `swift-conventions` covers code shape; `code-quality` covers architectural cleanliness and removal/simplification work.
- `test-strategy` is repo-specific verification guidance; `swift-testing-expert` is framework-level guidance for modern Swift Testing APIs and XCTest migration.
- `performance-profiling` covers app-level bottlenecks across GitMenuBar; `swiftui-performance-audit` is the narrow skill for SwiftUI invalidation, rendering, and profiling evidence.
- `swift-concurrency`, `swift-testing-expert`, and `swiftui-performance-audit` are installed external skills tracked in `skills-lock.json`.
- `global:thermo-nuclear-code-quality-review` is the generic strict review route; load the project-only profile named by `AGENTS.md` before judging GitMenuBar changes.
- `global:improve` is the generic advisory planning route; write executable plans under `plans/` and keep source-code changes out of scope.
- `delivery-workflow` owns risk lanes, validation, gates, and Git. Domain skills own menu-bar, macOS, Swift, security, concurrency, and release invariants.
- `global:` entries are external canonical skills, not local copies. Broken local links remain validation errors.

## Installed External Skills

- `avdlee/swift-concurrency-agent-skill@swift-concurrency`
- `avdlee/swift-testing-agent-skill@swift-testing-expert`
- `dimillian/skills@swiftui-performance-audit`

## Suggested Future Complement

- `avdlee/swiftui-agent-skill@swiftui-expert-skill`
