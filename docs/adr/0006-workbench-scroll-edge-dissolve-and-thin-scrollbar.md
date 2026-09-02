# Workbench scroll surfaces use native scrolling

Status: retired (2026-09-02). GitMenuBar uses the platform `ScrollView`/
`List` behavior for the main project content, Commit Details, Project Cleanup,
Command Palette, and the Projects sidebar. Native indicators remain available
and the system owns their interaction.

The former scroll-driven edge mask and custom AppKit thumb were removed because
they duplicated native affordances, added interaction state, and made the
surface harder to reason about with keyboard navigation, VoiceOver, and newer
system appearances. The original implementation is retained in repository
history for reference.
