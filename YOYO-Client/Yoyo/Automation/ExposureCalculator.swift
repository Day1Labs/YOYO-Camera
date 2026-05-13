import AVFoundation
import Foundation

// MARK: - EV control loop core

struct EVPlan {
    let iso: Int?
    let shutter: CMTime?
    let manualExposure: Bool
}

// MARK: - exposure calculator

final class ExposureCalculator {
    init() {}

    /// Calculate the ISO/shutter plan for the EV control loop
    func computeEVClosedLoopPlan(
        analysis: SceneAnalysis,
        baseExposureBias _: Float?,
        motionLevel: Double?
    ) -> EVPlan {
        // target brightness under subject metering and highlight protection
        let target: Float = computeTargetBrightness(
            analysis: analysis
        )

        // estimate the current relative exposure deviation(linear-domain approximation)
        // to reach the target, multiply by factor = target/avgB
        // the EV exposure difference is approximately log2(factor)
        let epsilon: Float = 1e-3
        let factor = target / max(analysis.averageBrightness, epsilon)
        let deltaEV = log2f(max(factor, 0.05))

        // Calculate the scene-required "slowest blur-free shutter" and "highest acceptable ISO"
        let minShutterSec = computeMinHandheldShutter(
            scene: analysis.sceneType,
            composition: analysis.composition,
            motionLevel: motionLevel
        )
        let maxISO = computeMaxAcceptableISO(
            scene: analysis.sceneType,
            lighting: analysis.lightingCondition
        )

        // start from the "baseline combination": ISO 100 and a base shutter speed(1/60)
        let baseISO = 100
        let baseShutterSec = 1.0 / 60.0
        // need to change total EV deltaEV = log2(S_new/S_base) + log2(ISO_new/ISO_base)
        // first satisfy shutter constraints:
        var candidateShutterSec = baseShutterSec
        var candidateISO = baseISO

        // First try to compensate exposure using shutter speed (longer or shorter), limited by minShutterSec and 1/4000..1s
        let desiredShutterSec = baseShutterSec * pow(2.0, Double(deltaEV))
        let clampedShutterSec = clampShutter(desiredShutterSec)

        // if a slower shutter is needed and falls below"slowest blur-free", then use"slowest blur-free"and hand the remaining EV to ISO
        let shutterAfterHandheld = max(clampedShutterSec, minShutterSec)
        candidateShutterSec = shutterAfterHandheld

        // calculate the remaining EV difference to be compensated by ISO
        let evByShutter = log2(candidateShutterSec / baseShutterSec)
        let remainingEV = Double(deltaEV) - evByShutter
        if remainingEV != 0 {
            let desiredISO = Double(baseISO) * pow(2.0, remainingEV)
            candidateISO = Int(desiredISO.rounded())
        }

        // clamp ISO
        candidateISO = min(max(candidateISO, 50), maxISO)

        // align shutter speed to 1/3 EV steps and consider anti-flicker
        let alignedBase = alignToStandardShutterSpeed(candidateShutterSec)
        let alignedShutter = alignToAntiFlicker(alignedBase)
        let shutterTime = shutterToCMTime(alignedShutter)

        // when to switch to"manual exposure"
        // - low light or night scenes, and there is obvious motion(avoid motion blur)
        // - or high-motion sports/stage scenes(sports/dance), require forced shutter speed
        let needsManual: Bool = {
            let isLow = (
                analysis.lightingCondition == .dark || analysis.lightingCondition == .dim
            )
            let fastScene = (
                analysis.sceneType == .sports
            )
            let moving = (motionLevel ?? 0) > 0.04
            return (isLow && moving) || fastScene
        }()

        if needsManual {
            return EVPlan(
                iso: candidateISO,
                shutter: shutterTime,
                manualExposure: true
            )
        } else {
            // Use an AE + exposure compensation loop to avoid conflicts with AE/flash/HDR
            return EVPlan(iso: nil, shutter: nil, manualExposure: false)
        }
    }

    /// Calculate the slowest blur-free shutter speed (considering motion/handheld), in seconds
    func computeMinHandheldShutter(scene: SceneType, composition: CompositionAnalysis, motionLevel: Double?) -> Double {
        // Equivalent focal length and OIS info are unavailable, so use heuristics plus scene tuning
        var minSec = 1.0 / 60.0

        switch scene {
        case .sports: minSec = 1.0 / 250.0
        case .pet: minSec = 1.0 / 200.0
        case .wildlife: minSec = 1.0 / 300.0
        case .portrait, .group: minSec = 1.0 / 125.0
        case .plant: minSec = 1.0 / 250.0
        default: break
        }

        // tighten slightly for multiple objects or when there is a subject
        if composition.hasMainSubject { minSec = max(minSec, 1.0 / 125.0) }
        if composition.faceCount > 1 { minSec = max(minSec, 1.0 / 160.0) }

        // smaller/farther subjects -> faster shutter
        if (composition.mainSubjectSize ?? 0) < 0.15 {
            minSec = max(minSec, 1.0 / 200.0)
        }

        // based on equivalent focal length(1/f rule)and (approximate) stabilization capability
        let eqFocal = CameraDeviceManager.shared.currentFocalLength
        // classic heuristic: slowest blur-free ≈ 1/equivalent focal length(seconds)
        var focalRule = 1.0 / max(10.0, eqFocal)
        // Approximation: rear wide/tele lenses are treated as having OIS, allowing about 1 stop of relaxation
        let hasOIS: Bool = {
            switch CameraDeviceManager.shared.currentCameraDeviceType {
            case .backWide, .telephoto: return true
            default: return false
            }
        }()
        if hasOIS { focalRule *= 1.5 }
        minSec = max(minSec, focalRule)

        // Dynamic adjustment: estimate motion from detected box displacement(0~1)
        if let m = motionLevel {
            if m > 0.08 {
                minSec = max(minSec, 1.0 / 250.0)
            } else if m > 0.04 {
                minSec = max(minSec, 1.0 / 160.0)
            } else if m > 0.02 {
                minSec = max(minSec, 1.0 / 125.0)
            }
        }

        return max(1.0 / 4000.0, min(minSec, 1.0))
    }

    /// Calculate the target brightness (subject metering + highlight protection)
    func computeTargetBrightness(analysis: SceneAnalysis) -> Float {
        var target: Float = 0.5 // middle gray
        let hist = analysis.histogram
        let comp = analysis.composition
        let lighting = analysis.lightingCondition

        // subject-region weighting(roughly): bias slightly brighter for large subjects, but lower it for small subjects against complex backgrounds
        if comp.hasMainSubject, let s = comp.mainSubjectSize, let pos = comp.mainSubjectPosition {
            // larger subjects get a slightly brighter target; very small ones are not over-boosted
            if s > 0.35 { target += 0.05 }
            else if s > 0.2 { target += 0.02 }
            // slightly brighten when centered or near rule-of-thirds intersections
            let dx = abs(Double(pos.x - 0.5))
            let dy = abs(Double(pos.y - 0.5))
            if dx < 0.2, dy < 0.2 { target += 0.01 }
        }

        // subject metering tendency: larger subject coverage allows a slightly brighter target for more pleasing skin tones
        if comp.hasMainSubject {
            if (comp.mainSubjectSize ?? 0) > 0.3 { target += 0.05 }
            if comp.faceCount > 0 { target += 0.03 }
        }
        // Bright/glare: lower the target slightly to protect highlights; raise it moderately in dark scenes
        switch lighting {
        case .glare:
            target -= 0.07
        case .bright:
            target -= 0.03
        case .dark:
            target += 0.04
        case .dim:
            target += 0.02
        case .normal:
            break
        }

        // highlight protection: lower the target when highlight ratio is high or overexposure is detected
        if hist.isOverexposed || hist.highlightRatio > 0.12 {
            target -= 0.07
        } else if hist.highlightRatio > 0.08 {
            target -= 0.04
        }

        // portrait skin-tone protection: when a face is present and the subject is large, reduce the target slightly to avoid overexposure
        if comp.faceCount > 0, (comp.mainSubjectSize ?? 0) > 0.2 {
            target -= 0.02
        }

        // Underexposure tendency: raise the target moderately in dark scenes while still prioritizing highlight protection(already handled above)

        // reasonable clamping
        target = max(0.35, min(0.6, target))
        return target
    }

    /// Calculate the highest acceptable ISO (simplified by scene/lighting)
    func computeMaxAcceptableISO(scene: SceneType, lighting: LightingCondition) -> Int {
        var maxISO = 1600
        switch lighting {
        case .dark, .dim: maxISO = 3200
        case .glare: maxISO = 400
        case .bright, .normal: maxISO = 1600
        }
        switch scene {
        case .cityscape, .general: maxISO = min(maxISO, 800)
        case .portrait, .group: maxISO = min(maxISO, 1600)
        case .sports: maxISO = max(maxISO, 3200)
        default: break
        }
        // combine with device capabilities
        if let caps = CameraDeviceManager.shared.getCurrentCameraCapabilities() {
            maxISO = min(maxISO, Int(caps.maxISO))
        }
        return max(100, min(6400, maxISO))
    }

    /// Clamp shutter speed to the likely device range (device capability unknown, currently 1/4000..1s)
    func clampShutter(_ sec: Double) -> Double {
        if let caps = CameraDeviceManager.shared.getCurrentCameraCapabilities() {
            let minS = max(1.0 / 40000.0, CMTimeGetSeconds(caps.minExposure))
            let maxS = max(1.0 / 60.0, CMTimeGetSeconds(caps.maxExposure))
            return max(minS, min(maxS, sec))
        }
        return max(1.0 / 4000.0, min(1.0, sec))
    }

    /// Convert seconds to CMTime
    func shutterToCMTime(_ seconds: Double) -> CMTime {
        if seconds >= 1.0 {
            let intSec = Int64(seconds.rounded())
            return CMTime(value: intSec, timescale: 1)
        } else {
            let denom = max(1, Int32((1.0 / seconds).rounded()))
            return CMTime(value: 1, timescale: denom)
        }
    }

    /// Align shutter speed to standard camera shutter values
    func alignToStandardShutterSpeed(_ seconds: Double) -> Double {
        // full set of 1/3 EV steps(typical photography sequence): including common denominators from 1/4000..1s
        let denominators: [Double] = [
            4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500,
            400, 320, 250, 200, 160, 125, 100, 80, 60, 50,
            40, 30, 25, 20, 15, 13, 10, 8, 6, 5,
            4, 3.2, 2.5, 2, 1.6, 1.3, 1,
        ]
        if seconds >= 1.0 { return seconds }
        let currentDen = 1.0 / seconds
        var best = denominators[0]
        var minDiff = abs(currentDen - best)
        for d in denominators {
            let diff = abs(currentDen - d)
            if diff < minDiff { minDiff = diff; best = d }
        }
        return 1.0 / best
    }

    /// Anti-flicker shutter alignment (50/60Hz), preferring safe values such as 1/100 or 1/120
    func alignToAntiFlicker(_ seconds: Double) -> Double {
        let hz = mainsFrequency()
        guard seconds < 1.0 else { return seconds }
        let safeDenoms60: [Double] = [
            120,
            60,
            240,
            180,
            90,
            30,
            15,
            100,
        ] // including 1/120, 1/60,... with 1/100 as a fallback
        let safeDenoms50: [Double] = [100, 50, 200, 25, 10]
        let candidates = hz == 60 ? safeDenoms60 : safeDenoms50
        let currentDen = 1.0 / seconds
        // force snapping only within the 1/30~1/250 range to avoid strong flicker bands
        if currentDen >= 30, currentDen <= 250 {
            var best = candidates[0]
            var minDiff = abs(currentDen - best)
            for d in candidates {
                let diff = abs(currentDen - d)
                if diff < minDiff { minDiff = diff; best = d }
            }
            return 1.0 / best
        }
        return seconds
    }

    /// Simple mains frequency inference
    func mainsFrequency() -> Int {
        let region = Locale.current.region?.identifier.uppercased() ?? ""
        // common 60Hz regions
        let sixty: Set<String> = [
            "US",
            "CA",
            "MX",
            "TW",
            "KR",
            "JP",
            "PH",
            "BR",
            "VE",
            "SA",
        ]
        return sixty.contains(region) ? 60 : 50
    }
}
