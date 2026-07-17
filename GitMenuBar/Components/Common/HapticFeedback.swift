import AppKit

enum HapticFeedback {
    static func actionSucceeded() {
        perform(.levelChange)
    }

    static func actionFailed() {
        perform(.generic)
    }

    static func actionUnavailable() {
        perform(.generic)
    }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        // AppKit's default performer selects the current input device and may
        // suppress feedback when hardware or user settings do not support it.
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
