import Combine
import SwiftData
import SwiftUI

/// Shared haptic feedback helper
@MainActor
private func triggerLightImpact() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

struct CameraControlView: View {
    private enum SwipeConfig {
        static let minimumDistance: CGFloat = 30
        static let downwardThreshold: CGFloat = 40
        static let leftTriggerRatio: CGFloat = 0.4
        static let rightTriggerRatio: CGFloat = 0.6
    }

    // Note: avoid observing high-frequency objects at the top level to prevent frequent redraws of the entire control view; child views observe them individually instead
    let latestPhoto: PhotoAsset?
    let managers: CameraManagersContainer

    /// Whether the drawer is expanded
    @Binding var isDrawerExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Bottom control bar
            BottomControlBar(
                latestPhoto: latestPhoto,
                managers: managers
            )
            .overlay(alignment: .bottomTrailing) {
                // Bottom-right entry button
                Button {
                    triggerLightImpact()
                    var transaction = Transaction(animation: .none)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isDrawerExpanded = true
                    }
                } label: {
                    ZStack {
                        Capsule()
                            .fill(.regularMaterial)
                            .environment(\.colorScheme, .dark)
                            .frame(width: 44, height: 16)

                        Capsule()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 20, height: 1.5)
                    }
                }
                .padding(
                    .trailing,
                    CameraControlDesign.horizontalPadding + (CameraControlDesign.filterButtonWidth - 44) / 2
                )
                .offset(y: 40) // Move the button downward only, so it sits closer to the bottom of the screen
            }
            .frame(height: CameraLayoutConfig.bottomControlHeight)
        }
    }
}

/// #Preview
struct CameraControlView_Previews: PreviewProvider {
    static var previews: some View {
        let managers = CameraManagersContainer()

        return CameraControlView(
            latestPhoto: nil,
            managers: managers,
            isDrawerExpanded: .constant(false)
        )
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
