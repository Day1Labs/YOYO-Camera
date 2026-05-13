import SwiftUI

/// Universal round glass texture button.
struct GlassCircleButton: View {
    let iconName: String
    let iconSize: CGFloat
    let foregroundColor: Color
    let action: () -> Void

    init(
        iconName: String,
        iconSize: CGFloat = 22,
        foregroundColor: Color = .white.opacity(0.9),
        action: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.iconSize = iconSize
        self.foregroundColor = foregroundColor
        self.action = action
    }

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        }) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(foregroundColor)
                .frame(width: 24, height: 24) // Unify icon space size
                .padding(20)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                        }
                }
        }
    }
}
