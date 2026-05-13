import Foundation

/// Unified threshold configuration for lighting analysis
public enum LightingThresholds {
    // MARK: - brightness thresholds

    /// Brightness boundaries for each lighting condition
    public enum Brightness {
        static let darkMaximum: Float = 0.12 // darkmaximum
        static let dimMinimum: Float = 0.12 // dimminimum
        static let dimMaximum: Float = 0.22 // dimmaximum
        static let normalMinimum: Float = 0.22 // normalminimum
        static let normalMaximum: Float = 0.75 // normalmaximum
        static let brightMinimum: Float = 0.75 // brightminimum
        static let brightMaximum: Float = 0.90 // brightmaximum
        static let glareMinimum: Float = 0.90 // glareminimum
    }

    // MARK: - Hysteresis thresholds

    /// Hysteresis thresholds used to reduce jitter
    public enum Hysteresis {
        static let darkLow: Float = 0.10 // darklower bound
        static let darkHigh: Float = 0.14 // darkupper bound
        static let dimLow: Float = 0.20 // dimlower bound
        static let dimHigh: Float = 0.24 // dimupper bound
        static let brightLow: Float = 0.73 // brightlower bound
        static let brightHigh: Float = 0.77 // brightupper bound
        static let glareLow: Float = 0.88 // glarelower bound
        static let glareHigh: Float = 0.92 // glareupper bound

        static let minConfidenceForChange: Float = 0.65 // Minimum confidence threshold
    }

    // MARK: - contrast thresholds

    public enum Contrast {
        static let lowThreshold: Float = 0.25 // Low contrast threshold
        static let normalThreshold: Float = 0.35 // normalcontrast thresholds
        static let highThreshold: Float = 0.55 // High contrast threshold
        static let veryHighThreshold: Float = 0.65 // Very high contrast threshold
    }

    // MARK: - shadow analysis thresholds

    public enum Shadow {
        static let hardShadowLow: Float = 0.55 // hard shadowslower bound
        static let hardShadowHigh: Float = 0.65 // hard shadowsupper bound
        static let edgeIntensityThreshold: Float = 0.3 // edge intensity threshold
    }

    // MARK: - light source analysis thresholds

    public enum LightSource {
        static let highlightThreshold: Float = 0.8 // Highlight threshold
        static let harshLightMinimum: Float = 0.3 // Minimum strong direct light ratio
        static let directionalLightMinimum: Float = 0.1 // Minimum directional light ratio
        static let directionalLightMaximum: Float = 0.3 // Maximum directional light ratio
        static let artificialLightMaximum: Float = 0.3 // Maximum artificial-light brightness
    }

    // MARK: - exposure compensation thresholds

    public enum Exposure {
        static let targetBrightness: Float = 0.5 // target brightness
        static let maxCompensation: Float = 2.0 // Maximum compensation
        static let minCompensation: Float = -2.0 // Minimum compensation
        static let adjustmentFactor: Float = 2.0 // adjustment scale factor
        static let overexposurePenalty: Float = 0.7 // overexposure penalty
        static let underexposureBonus: Float = 0.7 // underexposure compensation
    }

    // MARK: - performance optimization configuration

    public enum Performance {
        static let analysisImageSize: CGFloat = 100 // analysis image size
        static let histogramBinCount: Int = 256 // number of histogram bins
        static let dynamicRangeThreshold: Float = 0.001 // dynamic range threshold
    }

    // MARK: - time-related configuration

    public enum Time {
        static let goldenHourStart: Float = -4.0 // golden hour start(solar altitude angle)
        static let goldenHourEnd: Float = 10.0 // golden hour end
        static let blueHourStart: Float = -8.0 // blue hour start
        static let blueHourEnd: Float = -4.0 // blue hour end
        static let hysteresisMinutes: Float = 9.0 // time hysteresis tolerance(minutes)
    }
}
