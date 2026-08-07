# Global safe cleanup uses path-scoped shared-repository analysis

Status: proposed. GitMenuBar will expose global cleanup through path-scoped repository analysis and mutation services, not one `GitManager` per Monitored Project. The coordinator groups monitored checkout paths by Shared Repository, protects explicitly monitored worktrees, assigns each Cleanup Unit to one canonical project row, and executes local cleanup serially with immediate revalidation. This preserves ADR 0004's selected-project `GitManager` boundary while preventing duplicate candidates and cross-repository mutation races.

## Considered options

- Reuse the selected-project `GitManager` for every monitored project: rejected because its mutable state and repository context are intentionally single-project.
- Create one persistent `GitManager` per monitored project: rejected because it multiplies full refresh state and violates ADR 0004's lightweight monitoring boundary.
- Analyze each monitored path independently: rejected because linked worktrees would duplicate Cleanup Units and could receive duplicate mutation attempts.
