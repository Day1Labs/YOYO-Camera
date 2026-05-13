import CoreImage
import SwiftUI

extension FilterIdentifier {
    var config: FilterConfig {
        let filterInfo = info ?? FilterInfo(
            colorTemperature: .neutral,
            intensity: .moderate,
            descriptionKey: "filter_unknown_description",
            processingType: .builtin,
            chain: []
        )
        let filterName = displayName
        let primary = Color.white
        let secondary = Color.white.opacity(0.7)
        let background = Color.clear
        let border = Color.clear

        // Generate display text
        let secondaryText = filterInfo.inspired ?? ""
        let tertiaryText = filterInfo.colorTemperature.rawValue.uppercased()

        // Adjust card styles based on strength
        let cardStyle = createCardStyle(
            backgroundColor: background,
            primaryColor: primary,
            secondaryColor: secondary,
            borderColor: border,
            intensity: filterInfo.intensity
        )

        // Get the processing type from filterInfo, if it is a LUT type and the file name is empty, use the filter name
        let processingType: FilterProcessingType
        switch filterInfo.processingType {
        case let .lut(fileName) where fileName.isEmpty:
            processingType = .lut(name)
        default:
            processingType = filterInfo.processingType
        }

        return FilterConfig(
            identifier: self,
            processing: FilterProcessingConfig(
                processingType: processingType,
                chain: filterInfo.chain,
                defaultIntensity: defaultIntensity(for: filterInfo.intensity)
            ),
            display: FilterDisplayConfig(
                name: filterName,
                description: filterInfo.localizedDescription,
                cardStyle: cardStyle,
                primaryText: nil,
                secondaryText: secondaryText,
                tertiaryText: tertiaryText,
                imageName: name + "-bg",
                isFilmSimulation: isFilmSimulation
            )
        )
    }

    /// Create a card style
    private func createCardStyle(
        backgroundColor: Color,
        primaryColor: Color,
        secondaryColor: Color,
        borderColor: Color,
        intensity _: FilterIntensity
    ) -> FilterCardStyle {
        FilterCardStyle(
            backgroundColor: backgroundColor,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            shape: AnyShape(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
            ),
            borderColor: borderColor
        )
    }

    private func defaultIntensity(for intensity: FilterIntensity) -> Float {
        switch intensity {
        case .subtle:
            return FilterIntensityConstants.minIntensity + FilterIntensityConstants.intensityStep
        case .moderate:
            return FilterIntensityConstants.minIntensity + FilterIntensityConstants.intensityStep * 3
        case .strong:
            return FilterIntensityConstants.maxIntensity
        }
    }
}
