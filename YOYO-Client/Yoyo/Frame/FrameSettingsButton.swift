import SwiftUI

/// Photo frame toggle button component.
struct FrameSettingsButton: View, Equatable {
    @ObservedObject var frameManager: FrameManager
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap?()
        }) {
            ZStack {
                // Round background.
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 48, height: 48)

                // Photo frame preview icon.
                FramePreviewIcon(
                    isEnabled: frameManager.isEnabled
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    static func == (lhs: FrameSettingsButton, rhs: FrameSettingsButton) -> Bool {
        lhs.frameManager.isEnabled == rhs.frameManager.isEnabled
    }
}

/// Photo frame preview icon.
struct FramePreviewIcon: View {
    let isEnabled: Bool

    var body: some View {
        if isEnabled {
            // Use the unified frame icon when enabled.
            Image("Frame-icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            // Disabled state shows the frame icon with a slash.
            ZStack {
                Image("Frame-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .opacity(0.5)

                // Slash overlay.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 3, height: 30)
                    .rotationEffect(.degrees(-45))
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        // Enabled photo frame button.
        FrameSettingsButton(
            frameManager: {
                let manager = FrameManager.shared
                manager.isEnabled = true
                return manager
            }()
        )

        // Disabled photo frame button.
        FrameSettingsButton(
            frameManager: {
                let manager = FrameManager.shared
                manager.isEnabled = false
                return manager
            }(),
            onTap: {}
        )
    }
    .padding()
    .background(Color(red: 0.12, green: 0.12, blue: 0.12))
}
