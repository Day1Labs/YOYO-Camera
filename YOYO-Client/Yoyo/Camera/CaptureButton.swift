import SwiftUI

// MARK: - Capture Button Design Constants

private enum CaptureButtonDesign {
    /// Small-screen threshold (kept consistent with other camera controls)
    static let smallScreenThreshold: CGFloat = 390

    /// Whether the device has a small screen
    static var isSmallScreen: Bool {
        UIScreen.main.bounds.width < smallScreenThreshold
    }
}

/// Capture button
struct CaptureButton: View {
    /// Optimization: remove the unused `viewState` to avoid unnecessary refreshes
    @ObservedObject var settingsState: CameraSettingsState

    @State private var captureState: CaptureState = .idle

    private var isSmallScreen: Bool {
        CaptureButtonDesign.isSmallScreen
    }

    /// Base size constants (circular)
    private var outerWidth: CGFloat {
        isSmallScreen ? 68 : 76
    }

    private var outerHeight: CGFloat {
        outerWidth
    }

    private var innerWidth: CGFloat {
        isSmallScreen ? 60 : 68
    }

    private var innerHeight: CGFloat {
        innerWidth
    }

    // Optimization: adjust the stop button size for better visual balance inside the circular outer ring
    private let cancelWidth: CGFloat = 30
    private let cancelHeight: CGFloat = 24
    private let cancelCornerRadius: CGFloat = 4

    // Performance optimization: cache static gradients to avoid repeated calculations
    // Removed unused `outerRingGradient`

    // Removed unused `outerRingStyle`

    /// Computed property: inner button style with flat colors
    private var innerButtonStyle: Color {
        switch settingsState.currentCaptureMode {
        case .photo:
            return .white
        case .livePhoto:
            return .accentColor
        case .movie:
            return .red
        }
    }

    var action: (() -> Void)?

    var body: some View {
        Button(
            action: {
                action?()
            }) {
                ZStack {
                    // 2. Outer ring - circular with a frosted-glass look
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: outerWidth, height: outerHeight)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.3)
                        )

                    // 3. Inner button
                    let isPressed = captureState.isWaiting || captureState.isCapturing
                    RoundedRectangle(cornerRadius: isPressed ? cancelCornerRadius : innerHeight / 2)
                        .fill(innerButtonStyle)
                        .frame(
                            width: isPressed ? cancelWidth : innerWidth,
                            height: isPressed ? cancelHeight : innerHeight
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)

                    // 4. Capture-in-progress indicator
                    if captureState.isCapturing, settingsState.currentCaptureMode != .movie {
                        LoadingIndicator()
                            .frame(width: outerWidth, height: outerHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: outerWidth, height: outerHeight)
            .onReceive(NotificationCenter.default.publisher(for: .cameraCaptureStateChanged)) { notification in
                if let newState = notification.userInfo?[CameraNotificationKeys.captureState] as? CaptureState {
                    captureState = newState
                }
            }
    }
}
