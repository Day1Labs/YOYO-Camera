import AVFoundation
import CoreImage
import CoreLocation
import Foundation
import UIKit
import Vision

// MARK: - lighting condition enum

/// Lighting condition type
public enum LightingCondition: String, Codable {
    case dark // very dark/night
    case dim // dim/low light
    case normal // normal brightness
    case bright // bright
    case glare // glare/overexposed
}

// MARK: - supporting structs

/// shadow analysis result
public struct ShadowAnalysis {
    let isHardShadow: Bool // whether it is a hard shadow
    let shadowContrast: Float // shadow contrast
    let shadowDirection: ShadowDirection // shadow direction
    let edgeIntensity: Float // edge intensity

    static func `default`() -> ShadowAnalysis {
        ShadowAnalysis(
            isHardShadow: false,
            shadowContrast: 0.3,
            shadowDirection: .ambient,
            edgeIntensity: 0.3
        )
    }
}

/// shadow direction
public enum ShadowDirection {
    case fromTop // from above
    case fromBottom // from below
    case fromLeft // from the left
    case fromRight // from the right
    case ambient // ambient light (no obvious direction)
}

/// Light source analysis result
public struct LightSourceAnalysis {
    let highlightRatio: Float // highlight area ratio
    let lightSourceType: LightSourceType // Light source type
    let hasDirectionalLight: Bool // whether there is a directional light source

    static func `default`() -> LightSourceAnalysis {
        LightSourceAnalysis(
            highlightRatio: 0.1,
            lightSourceType: .ambient,
            hasDirectionalLight: false
        )
    }
}

/// Light source type
public enum LightSourceType {
    case harsh // strong direct light
    case directional // directional light source
    case diffused // diffuse light
    case artificial // artificial light
    case ambient // ambient light
}

/// Time context
public struct TimeContext {
    let season: Season // season
    let timeOfDay: TimeOfDay // time period
    let hour: Int // hour
    let solarElevation: Float // solar altitude angle(approximate, in degrees)
    let isGoldenPossible: Bool // whether it is close to golden hour
    let isBluePossible: Bool // whether it is close to blue hour
}

/// Time period enum (merged full version)
enum TimeOfDay: String, CaseIterable {
    case dawn // dawn/sunrise
    case sunrise // sunrise
    case morning // morning
    case midday // noon
    case afternoon // afternoon
    case sunset // sunset
    case evening // evening
    case dusk // dusk
    case blueHour // blue hour
    case night // night

    /// Get the Chinese description of the time period
    var displayName: String {
        switch self {
        case .dawn: return .timeDawn.localized
        case .sunrise: return .timeSunrise.localized
        case .morning: return .timeMorning.localized
        case .midday: return .timeMidday.localized
        case .afternoon: return .timeAfternoon.localized
        case .sunset: return .timeSunset.localized
        case .evening: return .timeEvening.localized
        case .dusk: return .timeDusk.localized
        case .blueHour: return .timeBlueHour.localized
        case .night: return .timeNight.localized
        }
    }
}

/// season
public enum Season {
    case spring // spring
    case summer // summer
    case autumn // autumn
    case winter // winter
}

/// Lighting analysis result
public struct LightingAnalysisResult {
    let condition: LightingCondition // lighting condition
    let confidence: Float // confidence
    let brightness: Float // brightness
    let contrast: Float // contrast
    let colorTemperature: ColorTemperature // color temperature
    let shadowAnalysis: ShadowAnalysis // shadow analysis
    let lightSourceAnalysis: LightSourceAnalysis // light source analysis
    let timeContext: TimeContext // Time context
    let analysisDetails: [String: Any] // detailed analysis data
    let exposureRecommendation: Float // exposure compensation suggestion

    /// Get the description of the exposure recommendation
    public var exposureDescription: String {
        let bias = exposureRecommendation
        if abs(bias) < 0.1 {
            return .exposureModerate.localized
        } else if bias > 0 {
            return .exposureIncrease.localized(bias)
        } else {
            return .exposureDecrease.localized(bias)
        }
    }
}

// MARK: - lighting analysis state management

/// Lighting analysis history state
private final class LightingAnalysisState {
    var recentResults: [LightingCondition] = []
    var lastCondition: LightingCondition?
    var lastBrightness: Float = 0.5
    var lastContrast: Float = 0.3
    var lastColorTemperature: ColorTemperature = .neutral
    var stableFrameCount: Int = 0
    let maxHistorySize = 5

    func addResult(_ condition: LightingCondition) {
        recentResults.append(condition)
        if recentResults.count > maxHistorySize {
            recentResults.removeFirst()
        }
    }

    func getMostFrequentCondition() -> LightingCondition? {
        guard !recentResults.isEmpty else { return nil }

        var counts: [LightingCondition: Int] = [:]
        for condition in recentResults {
            counts[condition, default: 0] += 1
        }

        return counts.max { $0.value < $1.value }?.key
    }

    func reset() {
        recentResults.removeAll()
        lastCondition = nil
        stableFrameCount = 0
    }
}

/// hysteresis threshold configuration
private enum HysteresisThresholds {
    // brightness thresholds(rising/falling)
    // Dark <-> Dim
    static let nightBrightnessLow: Float = 0.10 // enter Dark
    static let nightBrightnessHigh: Float = 0.15 // leave Dark

    // Dim <-> Normal
    static let lowLightBrightnessLow: Float = 0.25 // enter Dim
    static let lowLightBrightnessHigh: Float = 0.30 // leave Dim

    // Normal <-> Bright
    static let brightBrightnessLow: Float = 0.70 // leave Bright
    static let brightBrightnessHigh: Float = 0.75 // enter Bright

    // Bright <-> Glare
    static let glareBrightnessLow: Float = 0.88 // leave Glare
    static let glareBrightnessHigh: Float = 0.92 // enter Glare

    // contrast thresholds
    static let lowContrastLow: Float = 0.25
    static let lowContrastHigh: Float = 0.35

    static let highContrastLow: Float = 0.55
    static let highContrastHigh: Float = 0.65

    // edge intensity threshold
    static let hardShadowLow: Float = 0.55
    static let hardShadowHigh: Float = 0.65

    /// Minimum confidence threshold (lowered to improve responsiveness)
    static let minConfidenceForChange: Float = 0.55
}

// MARK: - main lighting analysis class

/// Professional lighting condition analyzer
/// Provides multi-dimensional lighting environment detection and analysis
public final class LightingAnalyzer {
    /// Singleton instance used for state management
    private static let shared = LightingAnalyzer()
    /// Shared CIContext to improve performance and avoid repeated creation
    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    private let state = LightingAnalysisState()
    private let stateLock = NSLock()

    private init() {}

    // MARK: - main public APIs

    /// Analyze lighting conditions (simplified API that returns only the condition)
    /// - Parameter sampleBuffer: camera sample buffer
    /// - Returns: lighting condition enum
    public static func analyzeLighting(from sampleBuffer: CMSampleBuffer) async -> LightingCondition {
        let result = await getLightingAnalysis(from: sampleBuffer)
        return result.condition
    }

    /// Quickly analyze lighting conditions (basic calculations only, optimized for performance)
    /// - Parameter sampleBuffer: camera sample buffer
    /// - Returns: lighting condition enum
    public static func analyzeLightingFast(from sampleBuffer: CMSampleBuffer) async -> LightingCondition {
        let brightness: Float

        // prefer the high-performance calculator (use a larger step size of 8 for faster sampling)
        if let stats = ImageStatisticsCalculator.analyze(from: sampleBuffer, stride: 8) {
            brightness = stats.averageBrightness
        } else {
            // Fallback
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return .normal
            }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            brightness = BrightnessCalculator.calculateAverageBrightness(ciImage: ciImage)
        }

        // simplified lighting condition judgment(without hysteresis)
        if brightness >= LightingThresholds.Brightness.glareMinimum {
            return .glare
        } else if brightness >= LightingThresholds.Brightness.brightMinimum {
            return .bright
        } else if brightness >= LightingThresholds.Brightness.normalMinimum {
            return .normal
        } else if brightness >= LightingThresholds.Brightness.dimMinimum {
            return .dim
        } else {
            return .dark
        }
    }

    /// Reset analysis state (used when switching scenes)
    public static func resetAnalysisState() {
        shared.stateLock.lock()
        defer { shared.stateLock.unlock() }
        shared.state.reset()
    }

    /// Get lighting analysis
    /// - Parameter sampleBuffer: camera sample buffer
    /// - Returns: Lighting analysis result
    public static func getLightingAnalysis(from sampleBuffer: CMSampleBuffer) async -> LightingAnalysisResult {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return createDefaultResult()
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        // 1. basic brightness and contrast analysis
        let brightnessResult = BrightnessCalculator.getBasicBrightnessAnalysis(from: sampleBuffer)
        let rawBrightness = brightnessResult.averageBrightness
        let rawContrast = brightnessResult.contrast
        let histogram = brightnessResult.histogram

        // 2. color temperature analysis
        let colorAnalysis = await ColorAnalyzer.getCompleteColorAnalysis(from: sampleBuffer)
        let rawColorTemperature = colorAnalysis.temperature
        let saturation = colorAnalysis.averageSaturation

        // 3. shadow distribution analysis
        let shadowDetails = await analyzeShadowDistribution(ciImage: ciImage)

        // 4. light source detection
        let lightSources = await detectLightSources(ciImage: ciImage)

        // 5. Time context
        let timeContext = getTimeContext()

        // 6. apply temporal smoothing(reduce smoothing strength to improve responsiveness)
        shared.stateLock.lock()
        let brightness = smoothValue(rawBrightness, last: shared.state.lastBrightness, alpha: 0.5)
        let contrast = smoothValue(rawContrast, last: shared.state.lastContrast, alpha: 0.5)
        let colorTemperature = smoothColorTemperature(rawColorTemperature, last: shared.state.lastColorTemperature)

        shared.state.lastBrightness = brightness
        shared.state.lastContrast = contrast
        shared.state.lastColorTemperature = colorTemperature
        shared.stateLock.unlock()

        // 7. determine the lighting condition comprehensively(brightness first with light hysteresis)
        let rawCondition = determineLightingConditionWithHysteresis(
            brightness: brightness,
            contrast: contrast,
            histogram: histogram,
            colorTemperature: colorTemperature,
            saturation: saturation,
            shadowDetails: shadowDetails,
            lightSources: lightSources,
            timeContext: timeContext
        )

        // 8. calculate confidence
        let confidence = calculateConfidence(
            condition: rawCondition,
            brightness: brightness,
            contrast: contrast,
            shadowDetails: shadowDetails,
            lightSources: lightSources,
            timeContext: timeContext
        )

        // 9. apply confidence thresholding and temporal stability
        let finalCondition = applyTemporalStability(
            rawCondition: rawCondition,
            confidence: confidence
        )

        // 10. build detailed analysis data
        let analysisDetails: [String: Any] = [
            "histogram": histogram,
            "saturation": saturation,
            "edgeIntensity": shadowDetails.edgeIntensity,
            "highlightRatio": lightSources.highlightRatio,
            "season": timeContext.season,
            "analysisTimestamp": Date(),
            "rawBrightness": rawBrightness,
            "smoothedBrightness": brightness,
        ]

        return LightingAnalysisResult(
            condition: finalCondition,
            confidence: confidence,
            brightness: brightness,
            contrast: contrast,
            colorTemperature: colorTemperature,
            shadowAnalysis: shadowDetails,
            lightSourceAnalysis: lightSources,
            timeContext: timeContext,
            analysisDetails: analysisDetails,
            exposureRecommendation: calculateExposureRecommendation(
                brightness: brightness,
                histogram: histogram
            )
        )
    }

    // MARK: - temporal smoothing and stability methods

    /// exponential moving average smoothing
    private static func smoothValue(_ current: Float, last: Float, alpha: Float) -> Float {
        alpha * current + (1 - alpha) * last
    }

    /// smooth color temperature changes
    private static func smoothColorTemperature(_ current: ColorTemperature, last _: ColorTemperature) -> ColorTemperature {
        // The previous logic would"freeze"color temperature, here it is changed tofollow the current result directly, avoid excessive lag
        current
    }

    /// Apply temporal stability based on confidence and history state
    private static func applyTemporalStability(
        rawCondition: LightingCondition,
        confidence: Float
    ) -> LightingCondition {
        shared.stateLock.lock()
        defer { shared.stateLock.unlock() }

        // add to history
        shared.state.addResult(rawCondition)

        // keep the previous result when confidence is low
        if confidence < HysteresisThresholds.minConfidenceForChange {
            if let lastCondition = shared.state.lastCondition {
                return lastCondition
            }
        }

        // enhanced temporal stability: require more stable frames during transitions
        if rawCondition == shared.state.lastCondition {
            shared.state.stableFrameCount += 1
        } else {
            shared.state.stableFrameCount = 0
        }

        // require at least 2 consistent frames during transitions, reduce jitter while improving responsiveness
        if rawCondition != shared.state.lastCondition {
            if shared.state.stableFrameCount < 2 {
                if let frequentCondition = shared.state.getMostFrequentCondition() {
                    return frequentCondition
                }
                if let lastCondition = shared.state.lastCondition {
                    return lastCondition
                }
            }
        }

        // update state
        shared.state.lastCondition = rawCondition
        return rawCondition
    }

    // MARK: - core analysis methods

    /// analyze shadow distribution features
    private static func analyzeShadowDistribution(ciImage: CIImage) async -> ShadowAnalysis {
        // use a more stable edge-detection filter
        guard let edgeFilter = CIFilter(name: "CIEdges") else {
            return ShadowAnalysis.default()
        }
        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let edgeImage = edgeFilter.outputImage else {
            return ShadowAnalysis.default()
        }

        // analyze edge intensity distribution
        let edgeIntensity = calculateEdgeIntensity(edgeImage)

        // detect hard vs. soft shadows(using hysteresis thresholds)
        let isHardShadow: Bool
        if edgeIntensity > HysteresisThresholds.hardShadowHigh {
            isHardShadow = true
        } else if edgeIntensity < HysteresisThresholds.hardShadowLow {
            isHardShadow = false
        } else {
            // within the hysteresis range, make a conservative judgment based on the current intensity
            isHardShadow = edgeIntensity > 0.6
        }

        let shadowContrast = edgeIntensity

        // analyze shadow direction(infer light source position)
        let shadowDirection = await analyzeShadowDirection(ciImage: ciImage)

        return ShadowAnalysis(
            isHardShadow: isHardShadow,
            shadowContrast: shadowContrast,
            shadowDirection: shadowDirection,
            edgeIntensity: edgeIntensity
        )
    }

    /// detect light sources in the image
    private static func detectLightSources(ciImage: CIImage) async -> LightSourceAnalysis {
        // measure the ratio of bright pixels directly on the original image, avoid using unstable threshold filters
        let highlightRatio = await calculateHighlightRatio(ciImage, originalImage: ciImage)

        // detect the light source type
        let lightSourceType = determineLightSourceType(
            highlightRatio: highlightRatio,
            averageBrightness: BrightnessCalculator.calculateAverageBrightness(ciImage: ciImage)
        )

        return LightSourceAnalysis(
            highlightRatio: highlightRatio,
            lightSourceType: lightSourceType,
            hasDirectionalLight: highlightRatio > 0.05 && highlightRatio < 0.3
        )
    }

    /// analyze shadow direction
    private static func analyzeShadowDirection(ciImage: CIImage) async -> ShadowDirection {
        // divide the image into 9 regions, analyze the brightness of each region
        let regions = divideImageIntoRegions(ciImage)
        let brightnesses = regions.map { BrightnessCalculator.calculateAverageBrightness(ciImage: $0) }

        // find the brightest and darkest regions
        let maxIndex = brightnesses.enumerated().max { $0.element < $1.element }?.offset ?? 4
        let minIndex = brightnesses.enumerated().min { $0.element < $1.element }?.offset ?? 4

        // infer light direction from the position of the brightest region
        switch maxIndex {
        case 0, 1, 2: return .fromTop
        case 6, 7, 8: return .fromBottom
        case 0, 3, 6: return .fromLeft
        case 2, 5, 8: return .fromRight
        default: return .ambient
        }
    }

    /// Determine the lighting condition using multi-dimensional weighted analysis
    private static func determineLightingConditionWithHysteresis(
        brightness: Float,
        contrast _: Float,
        histogram: HistogramAnalysis,
        colorTemperature _: ColorTemperature,
        saturation _: Float,
        shadowDetails: ShadowAnalysis,
        lightSources: LightSourceAnalysis,
        timeContext _: TimeContext
    ) -> LightingCondition {
        // get the previous decision for hysteresis comparison
        shared.stateLock.lock()
        let lastCondition = shared.state.lastCondition
        shared.stateLock.unlock()

        // 1. prioritize detectingglare/overexposed (Glare)
        // decision logic: extremely high brightness OR (relatively high brightness AND (strong direct light OR hard shadows OR severe overexposure))
        let isGlareState = lastCondition == .glare
        let glareThreshold = isGlareState ? HysteresisThresholds.glareBrightnessLow : HysteresisThresholds.glareBrightnessHigh

        let isHarshEnvironment = lightSources.lightSourceType == .harsh || shadowDetails.isHardShadow || histogram.isOverexposed
        // if the environment is harsh(strong light/hard shadows), lower Glare decision threshold
        let effectiveGlareThreshold = isHarshEnvironment ? (glareThreshold - 0.05) : glareThreshold

        if brightness >= effectiveGlareThreshold {
            return .glare
        }

        // 2. detect bright (Bright)
        let isBrightState = lastCondition == .bright
        let brightThreshold = isBrightState ? HysteresisThresholds.brightBrightnessLow : HysteresisThresholds.brightBrightnessHigh

        if brightness >= brightThreshold {
            return .bright
        }

        // 3. detect dark (Dark)
        // decision logic: extremely low brightness.
        let isDarkState = lastCondition == .dark
        let darkThreshold = isDarkState ? HysteresisThresholds.nightBrightnessHigh : HysteresisThresholds.nightBrightnessLow

        if brightness <= darkThreshold {
            return .dark
        }

        // 4. detect dim (Dim)
        let isDimState = lastCondition == .dim
        let dimThreshold = isDimState ? HysteresisThresholds.lowLightBrightnessHigh : HysteresisThresholds.lowLightBrightnessLow

        if brightness <= dimThreshold {
            return .dim
        }

        // 5. default to normal (Normal)
        return .normal
    }

    // MARK: - helper calculation methods

    /// calculateedge intensity
    private static func calculateEdgeIntensity(_ edgeImage: CIImage) -> Float {
        // calculate average edge intensity with an area-average filter
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.3 }

        avgFilter.setValue(edgeImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: edgeImage.extent), forKey: kCIInputExtentKey)

        guard let avgImage = avgFilter.outputImage else { return 0.3 }

        // use the shared context
        var pixel: [UInt8] = [0, 0, 0, 0]

        ciContext.render(avgImage, toBitmap: &pixel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        return Float(pixel[0]) / 255.0
    }

    /// divide the image into 9 regions
    private static func divideImageIntoRegions(_ ciImage: CIImage) -> [CIImage] {
        let extent = ciImage.extent
        let width = extent.width / 3
        let height = extent.height / 3

        var regions: [CIImage] = []

        for row in 0 ..< 3 {
            for col in 0 ..< 3 {
                let rect = CGRect(
                    x: extent.minX + CGFloat(col) * width,
                    y: extent.minY + CGFloat(row) * height,
                    width: width,
                    height: height
                )
                regions.append(ciImage.cropped(to: rect))
            }
        }

        return regions
    }

    /// calculate highlight ratio
    private static func calculateHighlightRatio(_: CIImage, originalImage: CIImage) async -> Float {
        // calculate the ratio of pixels above the brightness threshold in the original image(area ratio).avoid relying on non-public filters.
        let ciImage = originalImage
        // use the shared context
        let scaled = scaleImageForAnalysisLocal(ciImage)
        let extent = scaled.extent
        guard extent.width > 0, extent.height > 0 else { return 0.0 }

        let bytesPerPixel = 4
        let bytesPerRow = Int(extent.width) * bytesPerPixel
        let totalBytes = Int(extent.height) * bytesPerRow
        var pixelData = Data(count: totalBytes)
        let success = pixelData.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            ciContext.render(scaled, toBitmap: base, rowBytes: bytesPerRow, bounds: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return true
        }
        guard success else { return 0.0 }

        let threshold: Float = 0.8 // highlight threshold
        var brightCount = 0
        var totalCount = 0
        pixelData.withUnsafeBytes { bytes in
            let ptr = bytes.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
                let r = Float(ptr[i]) / 255.0
                let g = Float(ptr[i + 1]) / 255.0
                let b = Float(ptr[i + 2]) / 255.0
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if luminance >= threshold { brightCount += 1 }
                totalCount += 1
            }
        }
        if totalCount == 0 { return 0.0 }
        return min(1.0, Float(brightCount) / Float(totalCount))
    }

    /// local scaling function, avoid cross-file access to private methods
    private static func scaleImageForAnalysisLocal(_ ciImage: CIImage) -> CIImage {
        let targetSize: CGFloat = 100
        let originalSize = ciImage.extent.size
        guard originalSize.width > 0, originalSize.height > 0 else { return ciImage }
        let scale = min(targetSize / originalSize.width, targetSize / originalSize.height)
        if scale < 1.0 {
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            return ciImage.transformed(by: transform)
        }
        return ciImage
    }

    /// determine the light source type
    private static func determineLightSourceType(highlightRatio: Float, averageBrightness: Float) -> LightSourceType {
        if highlightRatio > 0.3 {
            return .harsh // strong direct light
        } else if highlightRatio > 0.1, averageBrightness > 0.6 {
            return .directional // directional light source
        } else if averageBrightness > 0.4, averageBrightness < 0.7 {
            return .diffused // diffuse light
        } else if averageBrightness < 0.3 {
            return .artificial // artificial light
        } else {
            return .ambient // ambient light
        }
    }

    /// get the time context
    public static func getTimeContext() -> TimeContext {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let minute = Calendar.current.component(.minute, from: now)
        let month = Calendar.current.component(.month, from: now)
        let timeDecimal = Float(hour) + Float(minute) / 60.0

        // season determination(Northern Hemisphere)
        let season: Season
        switch month {
        case 3 ... 5: season = .spring
        case 6 ... 8: season = .summer
        case 9 ... 11: season = .autumn
        default: season = .winter
        }

        // time-period judgment - use hysteresis logic to reduce boundary jitter
        let timeOfDay = determineTimeOfDayWithHysteresis(timeDecimal: timeDecimal)

        // approximate solar altitude angle(a simplified approximation when location is unavailable, use only as a prior, not a hard rule)
        let solarElevation = approximateSolarElevation(hourDecimal: timeDecimal, month: month)
        let isGolden = (solarElevation > LightingThresholds.Time.goldenHourStart && solarElevation < LightingThresholds.Time.goldenHourEnd)
        let isBlue = (solarElevation > LightingThresholds.Time.blueHourStart && solarElevation <= LightingThresholds.Time.blueHourEnd)

        return TimeContext(season: season,
                           timeOfDay: timeOfDay,
                           hour: hour,
                           solarElevation: solarElevation,
                           isGoldenPossible: isGolden,
                           isBluePossible: isBlue)
    }

    /// judge time periods using hysteresis logic
    private static func determineTimeOfDayWithHysteresis(timeDecimal: Float) -> TimeOfDay {
        // define time-period boundaries(center points)
        struct TimeRange {
            let start: Float
            let end: Float
            let timeOfDay: TimeOfDay
        }

        let ranges: [TimeRange] = [
            TimeRange(start: 4.5, end: 6.0, timeOfDay: .dawn),
            TimeRange(start: 6.0, end: 7.5, timeOfDay: .sunrise),
            TimeRange(start: 7.5, end: 11.0, timeOfDay: .morning),
            TimeRange(start: 11.0, end: 13.0, timeOfDay: .midday),
            TimeRange(start: 13.0, end: 17.0, timeOfDay: .afternoon),
            TimeRange(start: 17.0, end: 18.5, timeOfDay: .sunset),
            TimeRange(start: 18.5, end: 19.5, timeOfDay: .evening),
            TimeRange(start: 19.5, end: 20.5, timeOfDay: .dusk),
            TimeRange(start: 20.5, end: 21.5, timeOfDay: .blueHour),
        ]

        // hysteresis-aware matching(boundary tolerance)
        let hysteresis: Float = LightingThresholds.Time.hysteresisMinutes / 60.0

        for range in ranges {
            let adjustedStart = range.start - hysteresis
            let adjustedEnd = range.end + hysteresis

            if timeDecimal >= adjustedStart, timeDecimal < adjustedEnd {
                return range.timeOfDay
            }
        }

        // default to night
        return .night
    }

    /// approximately calculate the solar altitude angle(simplified when location is unavailable: use noon as the peak and adjust amplitude by season)
    private static func approximateSolarElevation(hourDecimal: Float, month: Int) -> Float {
        // map time to [0, 24)
        let t = max(0, min(24, hourDecimal))
        // a simplified sinusoidal model centered at 12:00, amplitude varies by season(higher in summer, lower in winter)
        let seasonFactor: Float
        switch month {
        case 6 ... 8: seasonFactor = 1.0 // summer
        case 3 ... 5, 9 ... 11: seasonFactor = 0.8 // spring/autumn
        default: seasonFactor = 0.6 // winter
        }
        // Peak altitude (degrees), roughly set to 60° * seasonFactor
        let peak: Float = 60.0 * seasonFactor
        // map time to [-pi, pi], where t=12 -> 0
        let x = (t - 12.0) / 12.0 * Float.pi
        return max(-10.0, peak * cos(x)) - 5.0 // shift downward by 5 degrees as an approximation below the horizon
    }

    /// calculate the confidence of the analysis result
    private static func calculateConfidence(
        condition: LightingCondition,
        brightness: Float,
        contrast _: Float,
        shadowDetails _: ShadowAnalysis,
        lightSources: LightSourceAnalysis,
        timeContext _: TimeContext
    ) -> Float {
        var confidence: Float = 0.85
        switch condition {
        case .glare:
            confidence = (brightness > 0.9 || lightSources.lightSourceType == .harsh) ? 0.95 : 0.9
        case .bright:
            confidence = 0.9
        case .normal:
            confidence = 0.85
        case .dim:
            confidence = brightness < 0.18 ? 0.9 : 0.85
        case .dark:
            confidence = brightness < 0.1 ? 0.95 : 0.9
        }
        return min(max(confidence, 0.0), 1.0)
    }

    /// calculate exposure compensation suggestions
    private static func calculateExposureRecommendation(brightness: Float, histogram: HistogramAnalysis) -> Float {
        // target brightness
        let targetBrightness = LightingThresholds.Exposure.targetBrightness
        var exposureBias: Float = 0

        // basic adjustment based on average brightness
        let brightnessDiff = targetBrightness - brightness
        exposureBias = brightnessDiff * LightingThresholds.Exposure.adjustmentFactor

        // fine-tuning based on histogram
        if histogram.isOverexposed {
            exposureBias -= LightingThresholds.Exposure.overexposurePenalty // lower exposure
        } else if histogram.isUnderexposed {
            exposureBias += LightingThresholds.Exposure.underexposureBonus // increase exposure
        }

        // limit to a reasonable range
        return max(LightingThresholds.Exposure.minCompensation, min(LightingThresholds.Exposure.maxCompensation, exposureBias))
    }

    /// create the default analysis result
    private static func createDefaultResult() -> LightingAnalysisResult {
        LightingAnalysisResult(
            condition: .normal,
            confidence: 0.5,
            brightness: 0.5,
            contrast: 0.3,
            colorTemperature: .neutral,
            shadowAnalysis: ShadowAnalysis.default(),
            lightSourceAnalysis: LightSourceAnalysis.default(),
            timeContext: getTimeContext(),
            analysisDetails: [:],
            exposureRecommendation: 0.0
        )
    }

    // MARK: - public utility methods

    /// get the description of the lighting condition
    public static func getDescription(for condition: LightingCondition) -> String {
        switch condition {
        case .dark: return String.lightingConditionDark.localized
        case .dim: return String.lightingConditionDim.localized
        case .normal: return String.lightingConditionNormal.localized
        case .bright: return String.lightingConditionBright.localized
        case .glare: return String.lightingConditionGlare.localized
        }
    }

    /// Recommend camera settings based on lighting conditions
    public static func recommendCameraSettings(for condition: LightingCondition, brightness _: Float) -> (exposureBias: Float, flashMode: AVCaptureDevice.FlashMode, whiteBalance: (temperature: Float, tint: Float)) {
        var exposureBias: Float = 0.0
        var flashMode: AVCaptureDevice.FlashMode = .off
        var whiteBalance: (temperature: Float, tint: Float) = (5500, 0)

        switch condition {
        case .dark:
            exposureBias = 0.7
            flashMode = .off
            whiteBalance = (3200, 0)
        case .dim:
            exposureBias = 0.5
            flashMode = .auto
            whiteBalance = (4000, 0)
        case .normal:
            exposureBias = 0.0
            flashMode = .auto
            whiteBalance = (5500, 0)
        case .bright:
            exposureBias = -0.2
            flashMode = .off
            whiteBalance = (5500, 0)
        case .glare:
            exposureBias = -0.5
            flashMode = .off
            whiteBalance = (5500, 0)
        }

        return (exposureBias: exposureBias, flashMode: flashMode, whiteBalance: whiteBalance)
    }
}

// MARK: - Extensions: LightingCondition convenience methods

extension LightingCondition: CustomStringConvertible {
    public var description: String {
        LightingAnalyzer.getDescription(for: self)
    }
}

extension LightingCondition: CaseIterable {
    public static var allCases: [LightingCondition] {
        [.dark, .dim, .normal, .bright, .glare]
    }
}

extension LightingCondition: Hashable {}
