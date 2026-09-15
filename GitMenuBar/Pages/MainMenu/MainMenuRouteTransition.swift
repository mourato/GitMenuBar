import SwiftUI

enum MainMenuRouteTransition {
    static func transition(for route: MainMenuRoute, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        switch route {
        case .main:
            return .opacity
        case .createRepo:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .move(edge: .bottom))
            )
        case .projectCleanup:
            return .opacity
        }
    }
}

extension AppPreferences.AppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .systemDefault:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
