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
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
