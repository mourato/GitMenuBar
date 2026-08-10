# Workbench scroll surfaces use shared edge dissolve and thin scrollbar

Status: accepted (2026-08-10). GitMenuBar will use one shared scroll treatment
for the main project content, Commit Details, Project Cleanup, and Command
Palette: a scroll-driven edge dissolve followed by a custom thin scrollbar.
The sidebar, sheets, and unrelated popovers remain outside this contract.

This ports Gordon's established behavior while adapting it to GitMenuBar's
fixed composer/footer layout and Workbench tokens. Native visible scrollers are
hidden on opted-in surfaces so the scrollbar remains above the dissolve; the
underlying `ScrollView` stays responsible for keyboard, VoiceOver, and
programmatic scrolling. The tradeoff is a small AppKit interaction bridge that
must be kept reusable, reduced-motion aware, and manually verified across the
four scroll owners.
