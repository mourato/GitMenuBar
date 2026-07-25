import CoreGraphics

/// Layout values shared by full-width native settings Forms.
enum SettingsFormLayoutPolicy {
    /// Matches `WorkbenchMetrics.windowPadding` so Form gutters stay on the workbench spacing grid.
    static let defaultOuterGutter: CGFloat = WorkbenchMetrics.windowPadding

    /// Returns the content guide width without imposing a maximum width.
    static func contentWidth(
        availableWidth: CGFloat,
        outerGutter: CGFloat = defaultOuterGutter
    ) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        return max(0, availableWidth - (max(0, outerGutter) * 2))
    }
}
