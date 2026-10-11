import AppKit

/// Animation on the AppKit side, honoring Reduce Motion as SwiftUI's views do
/// through `accessibilityReduceMotion`: under it, changes land at once.
@MainActor
enum Motion {
    static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Runs `changes` with no animation at all, as when the tree opens many rows at once.
    static func instantly(_ changes: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            changes()
        }
    }

    /// Runs `changes` (made through `animator()` proxies, or row height changes) over
    /// `duration`, or at once under Reduce Motion.
    static func animate(_ duration: TimeInterval, _ changes: () -> Void, completion: (@Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = isReduced ? 0 : duration
            context.allowsImplicitAnimation = !isReduced
            changes()
        }, completionHandler: completion)
    }
}
