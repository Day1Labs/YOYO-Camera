import SwiftUI

/// Defines the area in `Pager` that allows hits and listens to swipes
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public enum SwipeInteractionArea {
    /// All available space inside `Pager`
    case allAvailable

    /// Just the page frame
    case page
}
