import AVFoundation
import CoreGraphics
import CoreLocation
import Foundation

// MARK: - Automation plan (with toast)

struct AutomationPlan {
    let camera: CameraSettings
    let toasts: [(type: ToastType, message: String, duration: Double, customIcon: String?)]
    /// Filter list pending import (downloaded from URL)
    let pendingFilterImports: [(url: String, displayName: String?)]
}

// MARK: - Automation conditions

enum AutomationCondition: Hashable, Codable {
    // scene-related
    case sceneIs(SceneType)
    case sceneIsNot(SceneType)
    case sceneIn([SceneType])

    // lighting-related
    case lightingIs(LightingCondition)
    case lightingIsNot(LightingCondition)

    // composition-related
    case subjectSizeBelow(Float)
    case subjectSizeAbove(Float)
    case ruleOfThirdsAlignmentBelow(Float)
    case ruleOfThirdsAlignmentAbove(Float)
    case leadingLineStrengthAbove(Float)
    case visualBalanceBelow(Float)
    case visualBalanceAbove(Float)
    case backgroundIsSimple
    case backgroundIsComplex
    case backgroundIsModerate
    case hasMainSubject
    case subjectTypeIs(SubjectType)
    // Added: frame center-of-mass bias and balance
    case frameBiasLeft
    case frameBiasRight
    case frameBiasTop
    case frameBiasBottom
    case frameBalanced

    // object-detection-related
    case objectCountAbove(Int)
    case objectCountEquals(Int)
    case hasObject(label: String)

    // motion-related
    case motionLevelAbove(Double)
    case motionLevelBelow(Double)

    // histogram-related
    case highlightRatioAbove(Double)
    case highlightRatioBelow(Double)
    case isOverexposed

    /// list matching
    case lightingInList([LightingCondition])

    // time-related
    case timeInRange(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)
    case timeAfter(hour: Int, minute: Int)
    case timeBefore(hour: Int, minute: Int)
    case weekdayIs(Int) // 1=Sunday, 2=Monday,..., 7=Saturday
    case weekdayIn([Int])

    // date-related
    case dateIs(month: Int, day: Int) // specific date, e.g. January 1st
    case nthWeekdayOfMonth(month: Int, weekday: Int, nth: Int) // Nth weekday of a month, e.g. the third Monday of January
    case monthIs(Int) // specific month
    case monthIn([Int]) // multiple months

    // location-related
    case nearLocation(latitude: Double, longitude: Double, radiusMeters: Double)
    case insideRegion(centerLat: Double, centerLon: Double, radiusMeters: Double)
    case outsideRegion(centerLat: Double, centerLon: Double, radiusMeters: Double)

    // altitude-related
    case altitudeAbove(Double) // meters
    case altitudeBelow(Double) // meters
    case altitudeInRange(min: Double, max: Double) // meters

    // color-analysis-related
    case colorTemperatureIs(ColorTemperature)
    case colorTemperatureIsNot(ColorTemperature)
    case colorSaturationAbove(Float) // 0.0 - 1.0
    case colorSaturationBelow(Float) // 0.0 - 1.0
    case colorBrightnessAbove(Float) // 0.0 - 1.0
    case colorBrightnessBelow(Float) // 0.0 - 1.0
    case dominantColorCount(Int) // dominant color count equals
    case dominantColorCountAbove(Int) // dominant color count greater than
    case dominantColorCountBelow(Int) // dominant color count less than

    // capture-related
    case beforeCapture
    case afterCapture

    /// evaluation function
    func evaluate(with analysis: SceneAnalysis, motionLevel: Double? = nil, captureState: CaptureEventState? = nil) -> Bool {
        switch self {
        case let .sceneIs(type):
            return analysis.sceneType == type

        case let .sceneIsNot(type):
            return analysis.sceneType != type

        case let .sceneIn(types):
            return types.contains(analysis.sceneType)

        case let .lightingIs(condition):
            return analysis.lightingCondition == condition

        case let .lightingIsNot(condition):
            return analysis.lightingCondition != condition

        case let .subjectSizeBelow(size):
            return (analysis.composition.mainSubjectSize ?? 0.5) < size

        case let .subjectSizeAbove(size):
            return (analysis.composition.mainSubjectSize ?? 0.5) > size

        case let .ruleOfThirdsAlignmentBelow(score):
            return analysis.composition.ruleOfThirds.alignmentScore < score

        case let .ruleOfThirdsAlignmentAbove(score):
            return analysis.composition.ruleOfThirds.alignmentScore > score

        case let .leadingLineStrengthAbove(strength):
            return analysis.composition.leadingLines.leadingLineStrength > strength

        case let .visualBalanceBelow(threshold):
            return analysis.composition.visualBalance.overallBalance < threshold

        case let .visualBalanceAbove(threshold):
            return analysis.composition.visualBalance.overallBalance > threshold

        case .backgroundIsSimple:
            return analysis.composition.backgroundComplexity == .simple

        case .backgroundIsComplex:
            return analysis.composition.backgroundComplexity == .complex

        case .backgroundIsModerate:
            return analysis.composition.backgroundComplexity == .moderate

        case .hasMainSubject:
            return analysis.composition.hasMainSubject

        case let .subjectTypeIs(type):
            return analysis.composition.mainSubjectType == type

        // frame center-of-mass bias and balance
        case .frameBiasLeft:
            let w = analysis.composition.visualBalance.quadrantWeights
            let left = (w.indices.contains(0) ? w[0] : 0) + (w.indices.contains(2) ? w[2] : 0)
            let right = (w.indices.contains(1) ? w[1] : 0) + (w.indices.contains(3) ? w[3] : 0)
            return left > right + 0.1

        case .frameBiasRight:
            let w = analysis.composition.visualBalance.quadrantWeights
            let left = (w.indices.contains(0) ? w[0] : 0) + (w.indices.contains(2) ? w[2] : 0)
            let right = (w.indices.contains(1) ? w[1] : 0) + (w.indices.contains(3) ? w[3] : 0)
            return right > left + 0.1

        case .frameBiasTop:
            let w = analysis.composition.visualBalance.quadrantWeights
            let top = (w.indices.contains(0) ? w[0] : 0) + (w.indices.contains(1) ? w[1] : 0)
            let bottom = (w.indices.contains(2) ? w[2] : 0) + (w.indices.contains(3) ? w[3] : 0)
            return top > bottom + 0.1

        case .frameBiasBottom:
            let w = analysis.composition.visualBalance.quadrantWeights
            let top = (w.indices.contains(0) ? w[0] : 0) + (w.indices.contains(1) ? w[1] : 0)
            let bottom = (w.indices.contains(2) ? w[2] : 0) + (w.indices.contains(3) ? w[3] : 0)
            return bottom > top + 0.1

        case .frameBalanced:
            let hb = analysis.composition.visualBalance.horizontalBalance
            let vb = analysis.composition.visualBalance.verticalBalance
            return hb > 0.65 && vb > 0.65

        case let .objectCountAbove(count):
            return analysis.objectsDetected.count > count

        case let .objectCountEquals(count):
            return analysis.objectsDetected.count == count

        case let .hasObject(label):
            return analysis.objectsDetected.contains { $0.label.lowercased() == label.lowercased() }

        case let .motionLevelAbove(level):
            return (motionLevel ?? 0) > level

        case let .motionLevelBelow(level):
            return (motionLevel ?? 0) < level

        case let .highlightRatioAbove(ratio):
            return Double(analysis.histogram.highlightRatio) > ratio

        case let .highlightRatioBelow(ratio):
            return Double(analysis.histogram.highlightRatio) < ratio

        case .isOverexposed:
            return analysis.histogram.isOverexposed

        case let .lightingInList(conditions):
            return conditions.contains(analysis.lightingCondition)

        // time-related
        case let .timeInRange(startHour, startMinute, endHour, endMinute):
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: analysis.currentTime)
            guard let hour = components.hour, let minute = components.minute else { return false }
            let currentMinutes = hour * 60 + minute
            let startMinutes = startHour * 60 + startMinute
            let endMinutes = endHour * 60 + endMinute

            if startMinutes <= endMinutes {
                // time range within the same day
                return currentMinutes >= startMinutes && currentMinutes <= endMinutes
            } else {
                // time range crossing midnight
                return currentMinutes >= startMinutes || currentMinutes <= endMinutes
            }

        case let .timeAfter(hour, minute):
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: analysis.currentTime)
            guard let currentHour = components.hour, let currentMinute = components.minute else { return false }
            let currentMinutes = currentHour * 60 + currentMinute
            let targetMinutes = hour * 60 + minute
            return currentMinutes >= targetMinutes

        case let .timeBefore(hour, minute):
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: analysis.currentTime)
            guard let currentHour = components.hour, let currentMinute = components.minute else { return false }
            let currentMinutes = currentHour * 60 + currentMinute
            let targetMinutes = hour * 60 + minute
            return currentMinutes < targetMinutes

        case let .weekdayIs(weekday):
            let calendar = Calendar.current
            let currentWeekday = calendar.component(.weekday, from: analysis.currentTime)
            return currentWeekday == weekday

        case let .weekdayIn(weekdays):
            let calendar = Calendar.current
            let currentWeekday = calendar.component(.weekday, from: analysis.currentTime)
            return weekdays.contains(currentWeekday)

        // date-related
        case let .dateIs(month, day):
            let calendar = Calendar.current
            let components = calendar.dateComponents([.month, .day], from: analysis.currentTime)
            return components.month == month && components.day == day

        case let .nthWeekdayOfMonth(month, weekday, nth):
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: analysis.currentTime)
            guard let currentMonth = components.month, let currentWeekday = components.weekday else { return false }

            // check whether month and weekday match
            if currentMonth != month || currentWeekday != weekday {
                return false
            }

            // calculate which occurrence of the weekday the current date is in the month
            guard let currentDay = components.day, let currentYear = components.year else { return false }
            var dateComponents = DateComponents()
            dateComponents.year = currentYear
            dateComponents.month = month
            dateComponents.day = 1

            guard let firstDayOfMonth = calendar.date(from: dateComponents) else { return false }
            let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)

            // calculate the date of the first target weekday
            var daysToAdd = (weekday - firstWeekday + 7) % 7
            if daysToAdd == 0, firstWeekday != weekday {
                daysToAdd = 7
            }

            // calculate the date of the nth target weekday
            let targetDay = daysToAdd + 1 + (nth - 1) * 7

            return currentDay == targetDay

        case let .monthIs(month):
            let calendar = Calendar.current
            let currentMonth = calendar.component(.month, from: analysis.currentTime)
            return currentMonth == month

        case let .monthIn(months):
            let calendar = Calendar.current
            let currentMonth = calendar.component(.month, from: analysis.currentTime)
            return months.contains(currentMonth)

        // location-related
        case let .nearLocation(latitude, longitude, radiusMeters):
            guard let location = analysis.location else { return false }
            let targetLocation = CLLocation(latitude: latitude, longitude: longitude)
            let distance = location.distance(from: targetLocation)
            return distance <= radiusMeters

        case let .insideRegion(centerLat, centerLon, radiusMeters):
            guard let location = analysis.location else { return false }
            let centerLocation = CLLocation(latitude: centerLat, longitude: centerLon)
            let distance = location.distance(from: centerLocation)
            return distance <= radiusMeters

        case let .outsideRegion(centerLat, centerLon, radiusMeters):
            guard let location = analysis.location else { return false }
            let centerLocation = CLLocation(latitude: centerLat, longitude: centerLon)
            let distance = location.distance(from: centerLocation)
            return distance > radiusMeters

        // altitude-related
        case let .altitudeAbove(meters):
            guard let location = analysis.location else { return false }
            return location.altitude > meters

        case let .altitudeBelow(meters):
            guard let location = analysis.location else { return false }
            return location.altitude < meters

        case let .altitudeInRange(min, max):
            guard let location = analysis.location else { return false }
            return location.altitude >= min && location.altitude <= max

        // color-analysis-related
        case let .colorTemperatureIs(temperature):
            let currentTemp = ColorAnalyzer.calculateColorTemperature(from: analysis.dominantColors)
            return currentTemp == temperature

        case let .colorTemperatureIsNot(temperature):
            let currentTemp = ColorAnalyzer.calculateColorTemperature(from: analysis.dominantColors)
            return currentTemp != temperature

        case let .colorSaturationAbove(threshold):
            let saturation = ColorAnalyzer.calculateSaturation(from: analysis.dominantColors)
            return saturation > threshold

        case let .colorSaturationBelow(threshold):
            let saturation = ColorAnalyzer.calculateSaturation(from: analysis.dominantColors)
            return saturation < threshold

        case let .colorBrightnessAbove(threshold):
            var totalBrightness: Float = 0
            for color in analysis.dominantColors {
                var brightness: CGFloat = 0
                color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
                totalBrightness += Float(brightness)
            }
            let averageBrightness = analysis.dominantColors.isEmpty ? 0 : totalBrightness / Float(analysis.dominantColors.count)
            return averageBrightness > threshold

        case let .colorBrightnessBelow(threshold):
            var totalBrightness: Float = 0
            for color in analysis.dominantColors {
                var brightness: CGFloat = 0
                color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
                totalBrightness += Float(brightness)
            }
            let averageBrightness = analysis.dominantColors.isEmpty ? 0 : totalBrightness / Float(analysis.dominantColors.count)
            return averageBrightness < threshold

        case let .dominantColorCount(count):
            return analysis.dominantColors.count == count

        case let .dominantColorCountAbove(count):
            return analysis.dominantColors.count > count

        case let .dominantColorCountBelow(count):
            return analysis.dominantColors.count < count

        // capture-related
        case .beforeCapture:
            return captureState == .beforeCapture

        case .afterCapture:
            return captureState == .afterCapture
        }
    }
}

// MARK: - Capture event state

enum CaptureEventState {
    case beforeCapture
    case afterCapture
    case none
}

// MARK: - Automation actions

enum AutomationAction: Hashable, Codable {
    // Zoom
    case setZoom(Double)
    case multiplyZoom(Double)
    case clampZoom(min: Double, max: Double)

    // Exposure
    case setExposureBias(Float)
    case addExposureBias(Float)

    // Flash
    case setFlashMode(AVCaptureDevice.FlashMode)
    case setFlashModeIfAuto(AVCaptureDevice.FlashMode) // Only change when the current value is Auto

    // Focus
    case focusOnSubject
    case focusOnRuleOfThirds

    /// Filter
    case setFilter(FilterIdentifier)
    /// Import a filter from URL (download and apply)
    case importFilterFromURL(url: String, displayName: String?)

    // white balance
    case setWhiteBalance(temperature: Float, tint: Float)
    case setWhiteBalanceTemperature(Float)
    case setWhiteBalanceTint(Float)
    case adjustWhiteBalanceTemperature(Float) // relative adjustment
    case adjustWhiteBalanceTint(Float) // relative adjustment

    // ISO
    case setISO(Int)
    case adjustISO(Int) // relative adjustment
    case clampISO(min: Int, max: Int)

    // shutter speed
    case setShutterSpeed(Double) // in seconds
    case setShutterSpeedFraction(numerator: Int, denominator: Int) // e.g. 1/125
    case multiplyShutterSpeed(Double) // multiplier adjustment
    case clampShutterSpeed(min: Double, max: Double) // in seconds

    /// toast message
    case showToast(type: ToastType, message: String, duration: Double = 3.0)

    /// Execute action
    func apply(to settings: inout MutableCameraSettings, with analysis: SceneAnalysis) {
        switch self {
        case let .setZoom(value):
            settings.zoom = value
        case let .multiplyZoom(factor):
            let current = settings.zoom ?? 1.0
            settings.zoom = current * factor
        case let .clampZoom(minVal, maxVal):
            let current = settings.zoom ?? 1.0
            settings.zoom = max(minVal, min(current, maxVal))
        case let .setExposureBias(value):
            settings.exposureBias = value
        case let .addExposureBias(value):
            if let current = settings.exposureBias {
                settings.exposureBias = current + value
            } else {
                settings.exposureBias = value
            }
        case let .setFlashMode(mode):
            settings.flashMode = mode
        case let .setFlashModeIfAuto(mode):
            if settings.flashMode == .auto {
                settings.flashMode = mode
            }
        case .focusOnSubject:
            if let pos = analysis.composition.mainSubjectPosition {
                settings.focusPoint = pos
            }
        case .focusOnRuleOfThirds:
            if let subjectPos = analysis.composition.mainSubjectPosition {
                let adjustedX = min(max(subjectPos.x, 0.33), 0.67)
                let adjustedY = min(max(subjectPos.y, 0.33), 0.67)
                settings.focusPoint = CGPoint(x: adjustedX, y: adjustedY)
            }
        case let .setFilter(type):
            settings.filter = type
        case let .importFilterFromURL(url, displayName):
            settings.pendingFilterImports.append((url: url, displayName: displayName))
        // white balanceaction
        case let .setWhiteBalance(temperature, tint):
            settings.whiteBalance = (temperature, tint)
        case let .setWhiteBalanceTemperature(temperature):
            let currentTint = settings.whiteBalance?.tint ?? 0
            settings.whiteBalance = (temperature, currentTint)
        case let .setWhiteBalanceTint(tint):
            let currentTemp = settings.whiteBalance?.temperature ?? 5500
            settings.whiteBalance = (currentTemp, tint)
        case let .adjustWhiteBalanceTemperature(delta):
            let currentTemp = settings.whiteBalance?.temperature ?? 5500
            let currentTint = settings.whiteBalance?.tint ?? 0
            // color temperaturerange is typically 2000K - 8000K
            let newTemp = max(2000, min(currentTemp + delta, 8000))
            settings.whiteBalance = (newTemp, currentTint)
        case let .adjustWhiteBalanceTint(delta):
            let currentTemp = settings.whiteBalance?.temperature ?? 5500
            let currentTint = settings.whiteBalance?.tint ?? 0
            // tintrange is typically -150 - 150
            let newTint = max(-150, min(currentTint + delta, 150))
            settings.whiteBalance = (currentTemp, newTint)
        // ISO action
        case let .setISO(value):
            settings.iso = value
        case let .adjustISO(delta):
            if let current = settings.iso {
                settings.iso = max(50, current + delta)
            } else {
                settings.iso = max(50, 100 + delta)
            }
        case let .clampISO(minVal, maxVal):
            if let current = settings.iso {
                settings.iso = max(minVal, min(current, maxVal))
            }
        // shutter speedaction
        case let .setShutterSpeed(seconds):
            settings.shutterSpeed = CMTime(seconds: seconds, preferredTimescale: 1000)
        case let .setShutterSpeedFraction(numerator, denominator):
            let seconds = Double(numerator) / Double(denominator)
            settings.shutterSpeed = CMTime(seconds: seconds, preferredTimescale: 1000)
        case let .multiplyShutterSpeed(factor):
            if let current = settings.shutterSpeed {
                let currentSeconds = CMTimeGetSeconds(current)
                let newSeconds = currentSeconds * factor
                settings.shutterSpeed = CMTime(seconds: newSeconds, preferredTimescale: 1000)
            }
        case let .clampShutterSpeed(minVal, maxVal):
            if let current = settings.shutterSpeed {
                let currentSeconds = CMTimeGetSeconds(current)
                let clampedSeconds = max(minVal, min(currentSeconds, maxVal))
                settings.shutterSpeed = CMTime(seconds: clampedSeconds, preferredTimescale: 1000)
            }
        // toast message
        case let .showToast(type, message, duration):
            settings.toastMessages.append((type: type, message: message, duration: duration, customIcon: "square.stack.3d.up"))
        }
    }
}

// MARK: - Mutable camera settings (used during construction)

struct MutableCameraSettings {
    var zoom: Double?
    var focusPoint: CGPoint?
    var exposureBias: Float?
    var iso: Int?
    var shutterSpeed: CMTime?
    var filter: FilterIdentifier?
    var flashMode: AVCaptureDevice.FlashMode?
    var whiteBalance: (temperature: Float, tint: Float)?
    var toastMessages: [(type: ToastType, message: String, duration: Double, customIcon: String?)] = []
    /// Filter list pending import (URL download)
    var pendingFilterImports: [(url: String, displayName: String?)] = []

    func toImmutable() -> CameraSettings {
        CameraSettings(
            zoom: zoom,
            focusPoint: focusPoint,
            exposureBias: exposureBias,
            iso: iso,
            shutterSpeed: shutterSpeed,
            filter: filter,
            flashMode: flashMode,
            whiteBalance: whiteBalance
        )
    }
}

// MARK: - logical operators

enum ConditionLogic: String, CaseIterable, Codable {
    case and = "AND" // all conditions must be met
    case or = "OR" // any one condition is enough
}

// MARK: - Automation rule

struct AutomationRule: Identifiable, Codable {
    var id: String // Use a 6-digit short ID as the unique identifier
    var name: String
    var conditions: [AutomationCondition]
    var actions: [AutomationAction]
    var conditionLogic: ConditionLogic = .and // conditionlogical operators
    var priority: Int = 0 // priority: higher values execute later and override earlier ones
    var isEnabled: Bool = true
    var requireConfirmation: Bool? = true // whether confirmation is required before running
    var createdAt: Date = .init() // creation time
    var executionInterval: TimeInterval = 0 // execution interval in seconds; 0 means unlimited
    var shareCode: String? // latest share code

    /// Generate a globally unique 6-digit short ID (timestamp + random number -> Base36encoding)
    static func generateUniqueShortID() -> String {
        // get the current timestamp in seconds
        let timestamp = UInt64(Date().timeIntervalSince1970)

        // Use the last 4 digits of the timestamp (36^4 = 1,679,616) plus a 2-digit random number (36^2 = 1,296)
        let timestampPart = timestamp % 1_679_616 // 36^4
        let randomPart = UInt64.random(in: 0 ..< 1296) // 36^2

        // Combine: timestamp part * 1296 + random part
        let combined = timestampPart * 1296 + randomPart

        // Convert to Base36 and pad to 6 digits
        var result = String(combined, radix: 36, uppercase: true)

        // ensure a length of 6 by left-padding with 0 when needed
        while result.count < 6 {
            result = "0" + result
        }

        return result
    }

    /// initialize ID when creating a new rule
    init(id: String? = nil, name: String, conditions: [AutomationCondition], actions: [AutomationAction], conditionLogic: ConditionLogic = .and, priority: Int = 0, isEnabled: Bool = true, requireConfirmation: Bool? = true, createdAt: Date = Date(), executionInterval: TimeInterval = 0, shareCode: String? = nil) {
        self.id = id ?? Self.generateUniqueShortID()
        self.name = name
        self.conditions = conditions
        self.actions = actions
        self.conditionLogic = conditionLogic
        self.priority = priority
        self.isEnabled = isEnabled
        self.requireConfirmation = requireConfirmation
        self.createdAt = createdAt
        self.executionInterval = executionInterval
        self.shareCode = shareCode
    }

    func matches(_ analysis: SceneAnalysis, motionLevel: Double? = nil, captureState: CaptureEventState? = nil) -> Bool {
        guard isEnabled else { return false }

        // ifnocondition, treat asunconditional match (manual trigger)
        guard !conditions.isEmpty else { return false }

        // Evaluate conditions according to the logical operator
        switch conditionLogic {
        case .and:
            // all conditions must be met
            return conditions.allSatisfy { $0.evaluate(with: analysis, motionLevel: motionLevel, captureState: captureState) }

        case .or:
            // any one or more conditions are enough
            return conditions.contains { $0.evaluate(with: analysis, motionLevel: motionLevel, captureState: captureState) }
        }
    }

    /// Get display text for the execution interval
    var executionIntervalDisplayText: String {
        ExecutionIntervalSupport.displayText(for: executionInterval)
    }
}

// MARK: - analysis requirement types

struct AnalysisRequirements: Equatable {
    var needsObjectDetection: Bool = false
    var needsSceneClassification: Bool = false
    var needsComposition: Bool = false
    var needsLighting: Bool = false
    var needsColors: Bool = false

    /// whether any analysis is needed
    var needsAnyAnalysis: Bool {
        needsObjectDetection || needsSceneClassification || needsComposition || needsLighting || needsColors
    }

    /// compute requirements from conditions
    static func from(condition: AutomationCondition) -> AnalysisRequirements {
        var req = AnalysisRequirements()
        switch condition {
        // scene-related - depends on object detection for scene classification
        case .sceneIs, .sceneIsNot, .sceneIn:
            req.needsSceneClassification = true
            req.needsObjectDetection = true // scene classification depends on object detection

        // object-detection-related
        case .hasObject, .objectCountAbove, .objectCountEquals:
            req.needsObjectDetection = true

        // composition-related
        case .subjectSizeBelow, .subjectSizeAbove,
             .ruleOfThirdsAlignmentBelow, .ruleOfThirdsAlignmentAbove,
             .leadingLineStrengthAbove,
             .visualBalanceBelow, .visualBalanceAbove,
             .backgroundIsSimple, .backgroundIsComplex, .backgroundIsModerate,
             .hasMainSubject, .subjectTypeIs,
             .frameBiasLeft, .frameBiasRight, .frameBiasTop, .frameBiasBottom, .frameBalanced:
            req.needsComposition = true

        // lighting-related
        case .lightingIs, .lightingIsNot, .lightingInList:
            req.needsLighting = true

        // histogram-related - belongs to lighting analysis
        case .highlightRatioAbove, .highlightRatioBelow, .isOverexposed:
            req.needsLighting = true

        // color-analysis-related
        case .colorTemperatureIs, .colorTemperatureIsNot,
             .colorSaturationAbove, .colorSaturationBelow,
             .colorBrightnessAbove, .colorBrightnessBelow,
             .dominantColorCount, .dominantColorCountAbove, .dominantColorCountBelow:
            req.needsColors = true

        // Time, date, location, altitude, motion, and capture events do not require image analysis
        case .timeInRange, .timeAfter, .timeBefore, .weekdayIs, .weekdayIn,
             .dateIs, .nthWeekdayOfMonth, .monthIs, .monthIn,
             .nearLocation, .insideRegion, .outsideRegion,
             .altitudeAbove, .altitudeBelow, .altitudeInRange,
             .motionLevelAbove, .motionLevelBelow,
             .beforeCapture, .afterCapture:
            break
        }
        return req
    }

    /// merge two requirements
    mutating func merge(with other: AnalysisRequirements) {
        needsObjectDetection = needsObjectDetection || other.needsObjectDetection
        needsSceneClassification = needsSceneClassification || other.needsSceneClassification
        needsComposition = needsComposition || other.needsComposition
        needsLighting = needsLighting || other.needsLighting
        needsColors = needsColors || other.needsColors
    }
}

// MARK: - Automation engine

final class AutomationEngine: ObservableObject {
    @Published var rules: [AutomationRule] = []
    @Published var activeRules: [AutomationRule] = []
    @Published private(set) var analysisRequirements: AnalysisRequirements = .init()

    private let userDefaultsKey = "com.day1-labs.yoyo.automation.rules"

    init() {
        loadRules()
        updateAnalysisRequirements()
    }

    /// recalculate analysis requirements(called when rules change)
    private func updateAnalysisRequirements() {
        var requirements = AnalysisRequirements()
        for rule in rules where rule.isEnabled {
            for condition in rule.conditions {
                let conditionReq = AnalysisRequirements.from(condition: condition)
                requirements.merge(with: conditionReq)
            }
        }
        analysisRequirements = requirements
        print("📊 [DEBUG] 分析需求已更新: objects=\(requirements.needsObjectDetection), scene=\(requirements.needsSceneClassification), composition=\(requirements.needsComposition), lighting=\(requirements.needsLighting), colors=\(requirements.needsColors)")
    }

    func addRule(_ rule: AutomationRule, after afterRuleId: String? = nil) {
        if let afterId = afterRuleId, let afterIndex = rules.firstIndex(where: { $0.id == afterId }) {
            // insert after the specified rule
            rules.insert(rule, at: afterIndex + 1)
        } else {
            // append to the end by default
            rules.append(rule)
        }
        // sort by priority, when priorities are equal, sort by creation time descending(newest first)
        rules.sort {
            if $0.priority == $1.priority {
                return $0.createdAt > $1.createdAt
            }
            return $0.priority < $1.priority
        }
        saveRules()
        updateAnalysisRequirements()
        objectWillChange.send()
    }

    func updateRule(_ rule: AutomationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            rules.sort { $0.priority < $1.priority }
            saveRules()
            updateAnalysisRequirements()
            objectWillChange.send()
        }
    }

    func deleteRule(at indexSet: IndexSet) {
        rules.remove(atOffsets: indexSet)
        saveRules()
        updateAnalysisRequirements()
        objectWillChange.send()
    }

    func deleteRule(_ id: String) {
        rules.removeAll { $0.id == id }
        saveRules()
        updateAnalysisRequirements()
        objectWillChange.send()
    }

    /// Compose settings: returns an automation plan containing camera settings and toast messages, optionally limited to a subset of rules
    func composeSettings(for analysis: SceneAnalysis, motionLevel: Double? = nil, captureState: CaptureEventState? = nil, limitedTo limitedRules: [AutomationRule]? = nil) -> (plan: AutomationPlan, matchedRules: [AutomationRule]) {
        var settings = MutableCameraSettings()
        var matched: [AutomationRule] = []

        // 1. Default base configuration (set only in fully automated mode; manual triggers should not override unspecified settings)
        if limitedRules == nil {
            settings.zoom = 1.0
            settings.exposureBias = 0.0
            settings.flashMode = .auto
        }

        // 2. apply rules: if limitedRules is passed, apply that set directly; otherwise filter matching rules
        let rulesToApply: [AutomationRule]
        if let limited = limitedRules {
            rulesToApply = limited
            matched = limited // already filtered externally
        } else {
            rulesToApply = rules.filter { $0.matches(analysis, motionLevel: motionLevel, captureState: captureState) }
            matched = rulesToApply
        }
        for rule in rulesToApply {
            for action in rule.actions {
                action.apply(to: &settings, with: analysis)
            }
        }

        // 3. global constraints(keep consistent with ZoomManager: 1.0x - 10.0x)
        if let z = settings.zoom {
            settings.zoom = max(1.0, min(z, 10.0))
        }

        // update active rule state (used for UI display, only when not limited)
        if limitedRules == nil {
            DispatchQueue.main.async {
                self.activeRules = matched
            }
        }
        let plan = AutomationPlan(
            camera: settings.toImmutable(),
            toasts: settings.toastMessages,
            pendingFilterImports: settings.pendingFilterImports
        )
        return (plan, matched)
    }

    /// manually execute a single rule(without checking conditions)
    func executeRuleOnce(_ rule: AutomationRule, with analysis: SceneAnalysis) -> CameraSettings {
        var settings = MutableCameraSettings()

        // 2. apply all actions of the rule
        for action in rule.actions {
            action.apply(to: &settings, with: analysis)
        }

        // 3. global constraints(keep consistent with ZoomManager: 1.0x - 10.0x)
        if let z = settings.zoom {
            settings.zoom = max(1.0, min(z, 10.0))
        }

        return settings.toImmutable()
    }

    // MARK: - persistence

    private func saveRules() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(rules)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("✅ 规则已保存: \(rules.count) 条")
        } catch {
            print("❌ 保存规则失败: \(error)")
        }
    }

    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("ℹ️ 未找到已保存的规则，使用空列表")
            return
        }

        do {
            let decoder = JSONDecoder()
            rules = try decoder.decode([AutomationRule].self, from: data)
            print("✅ 已加载规则: \(rules.count) 条")
            updateAnalysisRequirements()
        } catch {
            print("❌ 加载规则失败: \(error)")
            rules = []
        }
    }
}

extension AVCaptureDevice.FlashMode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = AVCaptureDevice.FlashMode(rawValue: rawValue) ?? .off
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
