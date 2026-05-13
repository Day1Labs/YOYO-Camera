import SwiftUI

// Unified card style constants
public let kCardSpacing: CGFloat = 16
public let kCardInnerPadding: CGFloat = 20
public let kCardCornerRadius: CGFloat = 24

/// Universal card container for uniform padding, background, and rounded corners.
public struct GlassCard<Content: View>: View {
    public let cardColor: Color
    public let paddingValue: CGFloat
    public let cornerRadius: CGFloat
    public let content: Content

    public init(
        cardColor: Color = Color(white: 0.15),
        paddingValue: CGFloat = kCardInnerPadding,
        cornerRadius: CGFloat = kCardCornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.cardColor = cardColor
        self.paddingValue = paddingValue
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(paddingValue)
            .glassCardStyle(cardColor: cardColor, cornerRadius: cornerRadius)
    }
}

public struct GlassCardModifier: ViewModifier {
    public let cardColor: Color
    public let cornerRadius: CGFloat

    public init(cardColor: Color = Color(white: 0.15), cornerRadius: CGFloat = kCardCornerRadius) {
        self.cardColor = cardColor
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(cardColor.opacity(0.4))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public extension View {
    func glassCardStyle(
        cardColor: Color = Color(white: 0.15),
        cornerRadius: CGFloat = kCardCornerRadius
    ) -> some View {
        modifier(GlassCardModifier(cardColor: cardColor, cornerRadius: cornerRadius))
    }
}
