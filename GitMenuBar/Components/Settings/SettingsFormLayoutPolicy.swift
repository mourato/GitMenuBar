import CoreGraphics

enum SettingsFormLayoutPolicy {
    static let defaultOuterGutter: CGFloat = WorkbenchMetrics.windowPadding

    static func contentWidth(
        availableWidth: CGFloat,
        outerGutter: CGFloat = defaultOuterGutter
    ) -> CGFloat {
        guard availableWidth > 0 else { return 0 }
        return max(0, availableWidth - (max(0, outerGutter) * 2))
    }
}
