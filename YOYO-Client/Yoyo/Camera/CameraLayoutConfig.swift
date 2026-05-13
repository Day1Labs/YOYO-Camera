import SwiftUI

/// Centralized layout configuration for the camera view
enum CameraLayoutConfig {
    // MARK: - Layout Constants

    static var topMenuHeight: CGFloat {
        hasNotch ? 64 : 52
    }

    static let bottomControlHeight: CGFloat = 210

    static let drawerSheetHeight: CGFloat = 340

    // MARK: - Helper Properties

    static var hasNotch: Bool {
        guard let window = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .filter(\.isKeyWindow).first
        else {
            return false
        }
        return window.safeAreaInsets.top > 20
    }

    // MARK: - Computed Properties

    static func availableHeight(
        for geometry: GeometryProxy,
        bottomControlHeight: CGFloat
    ) -> CGFloat {
        geometry.size.height - topMenuHeight - bottomControlHeight
    }

    static func availableWidth(for geometry: GeometryProxy) -> CGFloat {
        geometry.size.width
    }
}
