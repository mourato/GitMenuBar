import SwiftUI

enum MacChromeMotion {
    static let micro: Animation = .easeOut(duration: 0.13)
    static let arrive: Animation = .snappy(duration: 0.30, extraBounce: 0.02)
    static let settle: Animation = .smooth(duration: 0.34)
    static let swap: Animation = .easeInOut(duration: 0.20)
    static let press: Animation = .spring(response: 0.15, dampingFraction: 1.0)
    static let route: Animation = .spring(response: 0.35, dampingFraction: 1.0)
    static let reduceMotion: Animation = .easeInOut(duration: 0.20)

    static func adaptive(_ animation: Animation, usesReducedMotion: Bool) -> Animation {
        usesReducedMotion ? reduceMotion : animation
    }
}
