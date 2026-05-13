import SwiftUI

/// filter strength constant
enum FilterIntensityConstants {
    /// Filter strength minimum value
    static let minIntensity: Float = 0.5
    /// Maximum filter strength
    static let maxIntensity: Float = 1.0
    /// Filter strength adjustment step size (for tactile feedback)
    static let intensityStep: Float = 0.1
}

/// Complete filter configuration
struct FilterConfig {
    let identifier: FilterIdentifier
    let processing: FilterProcessingConfig
    let display: FilterDisplayConfig
}

/// Filter application configuration
struct FilterProcessingConfig {
    let processingType: FilterProcessingType
    let chain: [FilterChainStep]?
    let defaultIntensity: Float // Default intensity, range 0.0 - 1.0

    init(processingType: FilterProcessingType, chain: [FilterChainStep]? = nil, defaultIntensity: Float = 1.0) {
        self.processingType = processingType
        self.chain = chain
        self.defaultIntensity = defaultIntensity
    }
}

/// Filter display configuration
struct FilterDisplayConfig {
    let name: String
    let description: String
    let cardStyle: FilterCardStyle
    let primaryText: String?
    let secondaryText: String?
    let tertiaryText: String?
    let imageName: String?
    let icon: AnyView?
    let borderColor: Color?
    let isFilmSimulation: Bool

    init(
        name: String,
        description: String,
        cardStyle: FilterCardStyle,
        primaryText: String? = nil,
        secondaryText: String? = nil,
        tertiaryText: String? = nil,
        imageName: String? = nil,
        icon: AnyView? = nil,
        borderColor: Color? = nil,
        isFilmSimulation: Bool = false
    ) {
        self.name = name
        self.description = description
        self.cardStyle = cardStyle
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.imageName = imageName
        self.icon = icon
        self.borderColor = borderColor
        self.isFilmSimulation = isFilmSimulation
    }
}
