import SwiftUI

// MARK: - Camera Control View Design Constants

/// Shared design constants for the camera control view
enum CameraControlDesign {
    /// Small-screen threshold (iPhone 12 mini and smaller)
    static let smallScreenThreshold: CGFloat = 390

    /// Whether the device has a small screen
    static var isSmallScreen: Bool {
        UIScreen.main.bounds.width < smallScreenThreshold
    }

    /// Side button size (gallery and filter buttons)
    static var sideButtonSize: CGFloat {
        isSmallScreen ? 40 : 48
    }

    /// Filter button width (slightly wider than its height)
    static var filterButtonWidth: CGFloat {
        sideButtonSize * 1.25
    }

    /// Bottom control bar padding
    static var bottomPadding: CGFloat {
        isSmallScreen ? 40 : 50
    }

    /// Horizontal padding for side buttons
    static var horizontalPadding: CGFloat {
        isSmallScreen ? 20 : 30
    }
}
