# Skills Index

Skill registry for GitMenuBar.

The catalog is organized by responsibility so agents can trigger the narrowest useful skill instead of loading overlapping guidance.

| Skill                       | Location                                    | Use When                                                                                                                |
| --------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `build-macos-apps`          | `.agents/skills/build-macos-apps/`          | Reproducing build, test, lint, or packaging failures and tracing them through local scripts/logs                        |
| `quality-assurance`         | `.agents/skills/quality-assurance/`         | Defining verification scope, merge gates, and manual checks for a change                                                |
| `release-management`        | `.agents/skills/release-management/`        | Preparing a release, validating DMGs, and checking release readiness                                                    |
| `macos-development`         | `.agents/skills/macos-development/`         | Working on SwiftUI/AppKit lifecycle, platform services, window ownership, and bridge boundaries                         |
| `menubar`                   | `.agents/skills/menubar/`                   | Changing `NSStatusItem`, popovers, app activation, and menu bar specific behavior                                       |
| `macos-design-guidelines`   | `.agents/skills/macos-design-guidelines/`   | Applying macOS HIG rules for menus, windows, keyboard, popovers, and accessibility                                      |
| `swift-conventions`         | `.agents/skills/swift-conventions/`         | Enforcing local Swift style, previews, naming, and safe structure in diffs                                              |
| `swift-concurrency`         | `.agents/skills/swift-concurrency/`         | Diagnosing data races, actor isolation, `Sendable` issues, async/await refactors, and Swift 6 migration                 |
| `code-quality`              | `.agents/skills/code-quality/`              | Refactors, deduplication, removal of dead code, and keeping architecture coherent                                       |
| `performance-profiling`     | `.agents/skills/performance-profiling/`     | Investigating startup cost, menu latency, rendering churn, memory growth, and expensive Git operations                  |
| `security-credentials`      | `.agents/skills/security-credentials/`      | Handling GitHub tokens, AI API keys, keychain access, migrations, and sensitive logging concerns                        |
| `accessibility-audit`       | `.agents/skills/accessibility-audit/`       | Reviewing keyboard access, VoiceOver, focus order, contrast, and reduced-motion behavior                                |
| `test-strategy`             | `.agents/skills/test-strategy/`             | Designing XCTest coverage, async tests, seams, doubles, and regression-oriented test plans                              |
| `swift-testing-expert`      | `.agents/skills/swift-testing-expert/`      | Using modern Swift Testing APIs, `#expect`/`#require`, traits, parameterized tests, async waiting, and XCTest migration |
| `swiftui-performance-audit` | `.agents/skills/swiftui-performance-audit/` | Auditing SwiftUI runtime performance, view invalidation, layout thrash, and when to request Instruments evidence        |

## Catalog Notes

- `build-macos-apps` is for reproduction and script routing; it is not the merge gate skill.
- `quality-assurance` owns verification depth and manual sign-off scope.
- `macos-development`, `menubar`, and `macos-design-guidelines` are intentionally separate:
  - `macos-development`: runtime and implementation mechanics
  - `menubar`: status item and popover invariants
  - `macos-design-guidelines`: HIG and desktop UX rules
- `swift-conventions` covers code shape; `code-quality` covers architectural cleanliness and removal/simplification work.
- `test-strategy` is repo-specific verification guidance; `swift-testing-expert` is framework-level guidance for modern Swift Testing APIs and XCTest migration.
- `performance-profiling` covers app-level bottlenecks across GitMenuBar; `swiftui-performance-audit` is the narrow skill for SwiftUI invalidation, rendering, and profiling evidence.
- `swift-concurrency`, `swift-testing-expert`, and `swiftui-performance-audit` are installed external skills tracked in `skills-lock.json`.

## Installed External Skills

- `avdlee/swift-concurrency-agent-skill@swift-concurrency`
- `avdlee/swift-testing-agent-skill@swift-testing-expert`
- `dimillian/skills@swiftui-performance-audit`

## Suggested Future Complement

- `avdlee/swiftui-agent-skill@swiftui-expert-skill`
