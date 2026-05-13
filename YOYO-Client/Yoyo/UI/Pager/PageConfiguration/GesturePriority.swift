import SwiftUI

/// Defines a set of priorities to interact with gestures
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public enum GesturePriority {
    /// Refers to `highPriorityGesture` modifier
    case high

    /// Refers to `simultaneousGesture` modifier
    case simultaneous

    /// Refers to `gesture` modifier
    case normal

    /// Default value, a.k.a, `normal`
    static let `default`: GesturePriority = .normal
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension View {
    func gesture(_ gesture: some Gesture, priority: GesturePriority) -> some View {
        Group {
            if priority == .high {
                highPriorityGesture(gesture)
            } else if priority == .simultaneous {
                simultaneousGesture(gesture)
            } else {
                self.gesture(gesture)
            }
        }
    }
}
