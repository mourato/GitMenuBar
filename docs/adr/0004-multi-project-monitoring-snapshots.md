# Multi-project monitoring uses lightweight snapshots

GitMenuBar will monitor multiple local projects through a persisted Monitored Projects list and immutable per-path Attention State snapshots, while keeping `GitManager` as the owner of the currently selected repository only. This avoids racing several repositories through the existing single-repository manager, keeps periodic monitoring cheap, and leaves full Git workflows scoped to the selected project.

Remote freshness is explicit: local project status may refresh automatically, but network fetches across projects are user-triggered so GitMenuBar does not surprise developers with latency, authentication prompts, or background remote mutations.
