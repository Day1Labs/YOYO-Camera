import Foundation
import UIKit

struct LutStats {
    let size: Int
    // Tone curve points for R, G, B channels (Input 0-1 vs Output 0-1)
    let redCurve: [CGPoint]
    let greenCurve: [CGPoint]
    let blueCurve: [CGPoint]

    /// Key color samples for visualization
    struct ColorSample {
        let name: String
        let inputColor: UIColor
        let outputColor: UIColor
    }

    let colorSamples: [ColorSample]
    let skinSamples: [ColorSample]

    // New: Grayscale Ramp (for Tonal Tint Bar)
    let grayscaleRamp: [UIColor]

    // New: HSL Shift Analysis
    struct HslShift {
        let name: String
        let inputColor: UIColor
        let outputColor: UIColor
        let hueShift: Float // -180 to 180 degrees
        let satChange: Float // multiplier (e.g. 1.2 = +20%)
        let lumChange: Float // multiplier
    }

    let hslShifts: [HslShift]

    // New: Saturation Response Curve (Input Sat vs Output Sat)
    let saturationCurves: [String: [CGPoint]]
    let luminanceSamples: [(input: Float, value: Float)]

    /// Split toning analysis
    struct SplitTone {
        let shadowTint: UIColor
        let highlightTint: UIColor
    }

    let splitTone: SplitTone

    /// Advanced Attributes
    struct Attributes {
        enum Temperature: String { case warm = "Warm", cool = "Cool", neutral = "Neutral" }
        enum Saturation: String { case high = "Vibrant", normal = "Natural", low = "Muted" }
        enum Contrast: String { case high = "High Contrast", normal = "Normal", faded = "Faded", matte = "Matte" }
        enum SkinTone: String { case natural = "Natural", shifted = "Shifted" }

        let temperature: Temperature
        let saturation: Saturation
        let contrast: Contrast
        let skinTone: SkinTone

        // Raw data for visualization
        let blackLevel: Float // 0-1
        let whiteLevel: Float // 0-1
        let avgSaturationDelta: Float // -1 to 1
        let skinHueShift: Float // degrees
    }

    let attributes: Attributes

    /// Auto-generated semantic tags
    let tags: [String]
}

enum LutAnalyzer {
    // MARK: - Constants

    private static let toneOffsets: [Float] = [0.25, 0.5, 0.75]

    private static let macbethColors: [(name: String, r: Float, g: Float, b: Float)] = [
        ("Dark Skin", 0.45, 0.32, 0.27),
        ("Light Skin", 0.76, 0.59, 0.51),
        ("Blue Sky", 0.38, 0.48, 0.62),
        ("Foliage", 0.34, 0.42, 0.26),
        ("Blue Flower", 0.52, 0.50, 0.69),
        ("Bluish Green", 0.40, 0.74, 0.67),
        ("Orange", 0.84, 0.49, 0.17),
        ("Purplish Blue", 0.31, 0.36, 0.65),
        ("Moderate Red", 0.76, 0.35, 0.39),
        ("Purple", 0.37, 0.24, 0.42),
        ("Yellow Green", 0.62, 0.74, 0.25),
        ("Orange Yellow", 0.88, 0.64, 0.18),
        ("Blue", 0.22, 0.24, 0.59),
        ("Green", 0.27, 0.58, 0.29),
        ("Red", 0.69, 0.21, 0.24),
        ("Yellow", 0.91, 0.78, 0.12),
        ("Magenta", 0.73, 0.34, 0.58),
        ("Cyan", 0.03, 0.52, 0.63),
        ("White", 0.95, 0.95, 0.95),
        ("Neutral 8", 0.78, 0.78, 0.78),
        ("Neutral 6.5", 0.63, 0.63, 0.63),
        ("Neutral 5", 0.48, 0.48, 0.47),
        ("Neutral 3.5", 0.33, 0.33, 0.33),
        ("Black", 0.20, 0.20, 0.20),
    ]

    private static let skinToneColors: [(name: String, r: Float, g: Float, b: Float)] = [
        ("Type I", 1.00, 0.88, 0.74),
        ("Type II", 0.99, 0.80, 0.66),
        ("Type III", 0.88, 0.67, 0.41),
        ("Type IV", 0.75, 0.45, 0.24),
        ("Type V", 0.44, 0.28, 0.20),
        ("Type VI", 0.32, 0.22, 0.22),
    ]

    private static let hslTargets: [(name: String, r: Float, g: Float, b: Float)] = [
        ("Red", 1, 0, 0),
        ("Orange", 1, 0.5, 0),
        ("Yellow", 1, 1, 0),
        ("Green", 0, 1, 0),
        ("Cyan", 0, 1, 1),
        ("Blue", 0, 0, 1),
        ("Purple", 0.5, 0, 1),
        ("Magenta", 1, 0, 1),
    ]

    private static let satHues: [(name: String, r: Float, g: Float, b: Float)] = [
        ("Red", 1, 0, 0),
        ("Green", 0, 1, 0),
        ("Blue", 0, 0, 1),
        ("Cyan", 0, 1, 1),
    ]

    /// Parses raw .cube data and extracts statistics
    static func analyze(lutData: Data, size: Int) -> LutStats? {
        guard let cubeString = String(data: lutData, encoding: .utf8) else {
            return nil
        }

        var cubeValues: [Float] = []
        let lines = cubeString.components(separatedBy: .newlines)

        // Basic parsing similar to FilterManager but we keep it simpler since we just need values
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") || trimmed.hasPrefix("LUT_3D_SIZE") || trimmed.hasPrefix("DOMAIN_MIN") || trimmed.hasPrefix("DOMAIN_MAX") {
                continue
            }
            let parts = trimmed.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 {
                cubeValues.append(contentsOf: parts)
            }
        }

        let expectedCount = size * size * size * 3
        guard cubeValues.count == expectedCount else {
            print("Analyzer: LUT data count mismatch")
            return nil
        }

        // Extract diagonal values for tone curve (where R=G=B in input space)
        // In a 3D LUT, the index is usually: z * size * size + y * size + x
        // For diagonal (grayscale input), input R=G=B.
        // Input indices range from 0 to size-1.
        // So we look for indices where x = y = z = i.
        func rec709Luma(_ r: Float, _ g: Float, _ b: Float) -> Float {
            0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        var redPoints: [CGPoint] = []
        var greenPoints: [CGPoint] = []
        var bluePoints: [CGPoint] = []
        var luminanceSamples: [(input: Float, value: Float)] = []

        for i in 0 ..< size {
            let inputVal = CGFloat(i) / CGFloat(size - 1)
            let index = (i * size * size + i * size + i) * 3
            if index + 2 < cubeValues.count {
                let rOut = CGFloat(cubeValues[index])
                let gOut = CGFloat(cubeValues[index + 1])
                let bOut = CGFloat(cubeValues[index + 2])
                redPoints.append(CGPoint(x: inputVal, y: rOut))
                greenPoints.append(CGPoint(x: inputVal, y: gOut))
                bluePoints.append(CGPoint(x: inputVal, y: bOut))
                luminanceSamples.append((Float(inputVal), rec709Luma(Float(rOut), Float(gOut), Float(bOut))))
            }
        }

        for offset in Self.toneOffsets {
            let combos: [(Float, Float, Float)] = [
                (offset, offset, offset * 0.8),
                (offset, offset * 0.8, offset),
                (offset * 0.8, offset, offset),
            ]
            for combo in combos {
                let output = sampleLut(r: combo.0, g: combo.1, b: combo.2, size: size, data: cubeValues)
                luminanceSamples.append((offset, rec709Luma(output.r, output.g, output.b)))
            }
        }

        var samples: [LutStats.ColorSample] = []
        for c in macbethColors {
            let out = sampleLut(r: c.r, g: c.g, b: c.b, size: size, data: cubeValues)
            samples.append(LutStats.ColorSample(
                name: c.name,
                inputColor: UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1.0),
                outputColor: UIColor(red: CGFloat(out.r), green: CGFloat(out.g), blue: CGFloat(out.b), alpha: 1.0)
            ))
        }

        var skinSamples: [LutStats.ColorSample] = []
        for c in Self.skinToneColors {
            let out = sampleLut(r: c.r, g: c.g, b: c.b, size: size, data: cubeValues)
            skinSamples.append(LutStats.ColorSample(
                name: c.name,
                inputColor: UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1.0),
                outputColor: UIColor(red: CGFloat(out.r), green: CGFloat(out.g), blue: CGFloat(out.b), alpha: 1.0)
            ))
        }

        // --- New Analysis: Grayscale Ramp ---
        var grayscaleRamp: [UIColor] = []
        let rampSteps = 12 // 0 to 11
        for i in 0 ..< rampSteps {
            let val = Float(i) / Float(rampSteps - 1)
            let out = sampleLut(r: val, g: val, b: val, size: size, data: cubeValues)
            grayscaleRamp.append(UIColor(red: CGFloat(out.r), green: CGFloat(out.g), blue: CGFloat(out.b), alpha: 1.0))
        }

        var hslShifts: [LutStats.HslShift] = []

        for t in Self.hslTargets {
            let inputColor = UIColor(red: CGFloat(t.r), green: CGFloat(t.g), blue: CGFloat(t.b), alpha: 1.0)
            let out = sampleLut(r: t.r, g: t.g, b: t.b, size: size, data: cubeValues)
            let outputColor = UIColor(red: CGFloat(out.r), green: CGFloat(out.g), blue: CGFloat(out.b), alpha: 1.0)

            var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

            inputColor.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
            outputColor.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)

            // Hue Shift
            var hueDiff = h2 - h1
            if hueDiff > 0.5 { hueDiff -= 1.0 }
            if hueDiff < -0.5 { hueDiff += 1.0 }
            let hueShiftDeg = Float(hueDiff * 360)

            // Saturation Change (avoid div by zero)
            let satChange = s1 > 0.01 ? Float(s2 / s1) : 1.0

            // Lum/Brightness Change
            let lumChange = b1 > 0.01 ? Float(b2 / b1) : 1.0

            hslShifts.append(LutStats.HslShift(
                name: t.name,
                inputColor: inputColor,
                outputColor: outputColor,
                hueShift: hueShiftDeg,
                satChange: satChange,
                lumChange: lumChange
            ))
        }

        func hsvBlend(base: (Float, Float, Float), saturation: Float) -> (Float, Float, Float) {
            let maxComponent = max(base.0, max(base.1, base.2))
            if maxComponent <= 0.0001 {
                let value = 1.0 - saturation
                return (value, value, value)
            }
            let normalized = (base.0 / maxComponent, base.1 / maxComponent, base.2 / maxComponent)
            let value: Float = 1.0
            let t = 1.0 - saturation
            return (
                normalized.0 * saturation + t * value,
                normalized.1 * saturation + t * value,
                normalized.2 * saturation + t * value
            )
        }

        func saturation(of color: (r: Float, g: Float, b: Float)) -> Float {
            let maxC = max(color.r, max(color.g, color.b))
            let minC = min(color.r, min(color.g, color.b))
            return maxC > 0 ? (maxC - minC) / maxC : 0
        }

        let satSteps = 20
        var satCurves: [String: [CGPoint]] = [:]

        for hue in Self.satHues {
            var points: [CGPoint] = []
            for i in 0 ... satSteps {
                let inputSat = Float(i) / Float(satSteps)
                let (rIn, gIn, bIn) = hsvBlend(base: (hue.r, hue.g, hue.b), saturation: inputSat)
                let out = sampleLut(r: rIn, g: gIn, b: bIn, size: size, data: cubeValues)
                let outSat = saturation(of: out)
                points.append(CGPoint(x: CGFloat(inputSat), y: CGFloat(outSat)))
            }
            satCurves[hue.name] = points
        }

        func averageSaturationDelta() -> Float {
            var total: Float = 0
            var count: Float = 0
            for curve in satCurves.values {
                guard let first = curve.first, let last = curve.last else { continue }
                let delta = Float(last.y - first.y)
                total += delta
                count += 1
            }
            if count == 0 { return 0 }
            return total / count
        }

        let avgSatDelta = averageSaturationDelta()

        // --- New Analysis: Split Toning ---
        let shadowIn: Float = 0.1
        let highlightIn: Float = 0.9

        let shadowOut = sampleLut(r: shadowIn, g: shadowIn, b: shadowIn, size: size, data: cubeValues)
        let highlightOut = sampleLut(r: highlightIn, g: highlightIn, b: highlightIn, size: size, data: cubeValues)

        let splitTone = LutStats.SplitTone(
            shadowTint: UIColor(red: CGFloat(shadowOut.r), green: CGFloat(shadowOut.g), blue: CGFloat(shadowOut.b), alpha: 1.0),
            highlightTint: UIColor(red: CGFloat(highlightOut.r), green: CGFloat(highlightOut.g), blue: CGFloat(highlightOut.b), alpha: 1.0)
        )

        // --- New Analysis: Advanced Attributes ---
        let blackOut = sampleLut(r: 0, g: 0, b: 0, size: size, data: cubeValues)
        let whiteOut = sampleLut(r: 1, g: 1, b: 1, size: size, data: cubeValues)

        func getLuma(_ r: Float, _ g: Float, _ b: Float) -> Float {
            0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        let blackLuma = getLuma(blackOut.r, blackOut.g, blackOut.b)
        let whiteLuma = getLuma(whiteOut.r, whiteOut.g, whiteOut.b)

        var contrast: LutStats.Attributes.Contrast = .normal
        if blackLuma > 0.05 {
            contrast = .faded
        } else if whiteLuma < 0.90 {
            contrast = .matte
        } else if blackLuma < 0.01 && whiteLuma > 0.99 {
            contrast = .high
        }

        // 2. Temperature (Multi-Gray Lab Analysis)
        let neutralLevels: [Float] = [0.25, 0.5, 0.75]
        var neutralLabs: [(Float, Float, Float)] = []
        for level in neutralLevels {
            let sample = sampleLut(r: level, g: level, b: level, size: size, data: cubeValues)
            neutralLabs.append(LutAnalyzer.rgbToLab(r: sample.r, g: sample.g, b: sample.b))
        }

        let labCount = Float(max(neutralLabs.count, 1))
        let avgA = neutralLabs.map(\.1).reduce(0, +) / labCount
        let avgB = neutralLabs.map(\.2).reduce(0, +) / labCount
        let chroma = sqrtf(avgA * avgA + avgB * avgB)
        let hueRadians = Float(atan2(Double(avgB), Double(avgA)))
        var hueDegrees = hueRadians * 180 / Float.pi
        if hueDegrees < 0 {
            hueDegrees += 360
        }

        var temp: LutStats.Attributes.Temperature = .neutral
        let chromaThreshold: Float = 1.0

        // Revised Temperature Logic based on Human Perception:
        // Warm: Red (0°), Orange, Yellow (90°). Range: [335°, 360°] U [0°, 115°]
        // Cool: Cyan, Blue (270°). Range: [195°, 305°]
        // Neutral/Green/Purple regions are left as .neutral

        if chroma >= chromaThreshold {
            if hueDegrees <= 115 || hueDegrees >= 335 {
                temp = .warm
            } else if hueDegrees >= 195, hueDegrees <= 305 {
                temp = .cool
            }
        }

        // 3. Saturation Impact
        // Sample pure Red, Green, Blue
        let primaries: [(r: Float, g: Float, b: Float)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1),
        ]

        func getSat(_ r: Float, _ g: Float, _ b: Float) -> Float {
            let maxV = max(r, max(g, b))
            let minV = min(r, min(g, b))
            if maxV == 0 { return 0 }
            return (maxV - minV) / maxV
        }

        var sat: LutStats.Attributes.Saturation = .normal
        if avgSatDelta > 0.05 {
            sat = .high
        } else if avgSatDelta < -0.15 {
            sat = .low
        }

        // 4. Skin Tone Protection
        func getHue(_ r: Float, _ g: Float, _ b: Float) -> Float {
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: &a)
            return Float(h)
        }

        var totalSkinHueDiff: Float = 0
        var maxSkinHueDiff: Float = 0

        for skin in Self.skinToneColors {
            let skinIn = (r: skin.r, g: skin.g, b: skin.b)
            let skinOut = sampleLut(r: skinIn.r, g: skinIn.g, b: skinIn.b, size: size, data: cubeValues)

            let skinInHue = getHue(skinIn.r, skinIn.g, skinIn.b)
            let skinOutHue = getHue(skinOut.r, skinOut.g, skinOut.b)

            var diff = abs(skinOutHue - skinInHue)
            if diff > 0.5 { diff = 1.0 - diff }

            totalSkinHueDiff += diff
            if diff > maxSkinHueDiff {
                maxSkinHueDiff = diff
            }
        }

        let avgSkinHueDiff = totalSkinHueDiff / Float(max(1, Self.skinToneColors.count))
        let skinTone: LutStats.Attributes.SkinTone = (maxSkinHueDiff < 0.05) ? .natural : .shifted

        let attributes = LutStats.Attributes(
            temperature: temp,
            saturation: sat,
            contrast: contrast,
            skinTone: skinTone,
            blackLevel: blackLuma,
            whiteLevel: whiteLuma,
            avgSaturationDelta: avgSatDelta,
            skinHueShift: avgSkinHueDiff
        )

        // --- Tag Generation Logic ---
        var tags: [String] = []

        if avgSatDelta < -0.85 {
            tags.append("B&W")
        } else {
            if temp == .warm { tags.append("Warm") }
            else if temp == .cool { tags.append("Cool") }

            if avgSatDelta > 0.1 {
                tags.append("Vibrant")
            } else if avgSatDelta < -0.2 {
                tags.append("Muted")
            }
        }

        // 2. Contrast & Mood
        if contrast == .faded || blackLuma > 0.02 { tags.append("Vintage") }
        else if contrast == .high { tags.append("Punchy") }
        else if contrast == .matte { tags.append("Matte") }

        // 3. Cinematic Looks (Teal & Orange Detection)
        var shH: CGFloat = 0, shS: CGFloat = 0, shB: CGFloat = 0, shA: CGFloat = 0
        splitTone.shadowTint.getHue(&shH, saturation: &shS, brightness: &shB, alpha: &shA)

        var hlH: CGFloat = 0, hlS: CGFloat = 0, hlB: CGFloat = 0, hlA: CGFloat = 0
        splitTone.highlightTint.getHue(&hlH, saturation: &hlS, brightness: &hlB, alpha: &hlA)

        // Hue ranges: Orange (0-0.1 or 0.9-1.0), Teal (0.4-0.6)
        let isTealShadow = (shS > 0.05) && (shH > 0.4 && shH < 0.6)
        let isOrangeHighlight = (hlS > 0.05) && (hlH < 0.12 || hlH > 0.95)
        let isWarmHighlight = (hlS > 0.05) && (hlH < 0.16 || hlH > 0.90) // Wider range for warm

        if isTealShadow && isOrangeHighlight {
            tags.append("Teal & Orange")
        } else if isTealShadow && isWarmHighlight {
            tags.append("Cinematic")
        }

        // 4. Portrait Optimization
        // Natural skin tone + not too high contrast + not too vibrant
        if skinTone == .natural && contrast != .high && sat != .high {
            tags.append("Portrait")
        }

        // 5. Nature/Landscape
        // If Greens are boosted or shifted nicely? (Simplified check)
        // Check Green primary saturation boost
        let greenIn = (r: Float(0), g: Float(1), b: Float(0))
        let greenOut = sampleLut(r: greenIn.r, g: greenIn.g, b: greenIn.b, size: size, data: cubeValues)
        let greenSat = getSat(greenOut.r, greenOut.g, greenOut.b)
        if greenSat > 0.9 && sat == .high {
            tags.append("Landscape")
        }

        // 6. Usage Suggestion (Photo vs Video)
        // Calculate scores based on attributes
        var videoScore = 0
        var photoScore = 0

        // Video affinities
        if tags.contains("Cinematic") || tags.contains("Teal & Orange") { videoScore += 4 }
        if contrast == .faded || contrast == .matte { videoScore += 3 }
        if contrast == .normal { videoScore += 1 }
        if skinTone == .natural { videoScore += 2 }
        if sat == .normal || sat == .low { videoScore += 1 }
        // Lifted blacks are very common in video grades
        if blackLuma > 0.03 { videoScore += 1 }

        // Photo affinities
        if contrast == .high { photoScore += 3 }
        if sat == .high { photoScore += 3 }
        if tags.contains("B&W") { photoScore += 4 } // Black and white is classically photographic
        if tags.contains("Landscape") { photoScore += 2 }
        if tags.contains("Punchy") { photoScore += 3 }
        // Shifted skin tones are often acceptable/desired in artistic photography but bad for video
        if skinTone == .shifted { photoScore += 1 }

        var usageTags: [String] = []
        // Determine primary usage
        if videoScore > photoScore + 1 {
            usageTags.append("Video")
        } else if photoScore > videoScore + 1 {
            usageTags.append("Photo")
        } else {
            // If scores are close, it's versatile
            usageTags.append("Universal")
        }

        // Insert at the beginning
        tags.insert(contentsOf: usageTags, at: 0)

        return LutStats(
            size: size,
            redCurve: redPoints,
            greenCurve: greenPoints,
            blueCurve: bluePoints,
            colorSamples: samples,
            skinSamples: skinSamples,
            grayscaleRamp: grayscaleRamp,
            hslShifts: hslShifts,
            saturationCurves: satCurves,
            luminanceSamples: luminanceSamples,
            splitTone: splitTone,
            attributes: attributes,
            tags: tags
        )
    }

    private static func rgbToLab(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        func srgbToLinear(_ c: Float) -> Float {
            if c <= 0.04045 {
                return c / 12.92
            } else {
                return powf((c + 0.055) / 1.055, 2.4)
            }
        }
        let rLin = srgbToLinear(max(0, min(r, 1)))
        let gLin = srgbToLinear(max(0, min(g, 1)))
        let bLin = srgbToLinear(max(0, min(b, 1)))

        let x = (0.4124564 * rLin + 0.3575761 * gLin + 0.1804375 * bLin) / 0.95047
        let y = (0.2126729 * rLin + 0.7151522 * gLin + 0.0721750 * bLin) / 1.00000
        let z = (0.0193339 * rLin + 0.1191920 * gLin + 0.9503041 * bLin) / 1.08883

        func pivot(_ t: Double) -> Double {
            t > pow(6.0 / 29.0, 3.0) ? pow(t, 1.0 / 3.0) : (t * (29.0 / 6.0) * (29.0 / 6.0) / 3.0) + (4.0 / 29.0)
        }

        let fx = pivot(Double(x))
        let fy = pivot(Double(y))
        let fz = pivot(Double(z))

        let l = Float((116.0 * fy) - 16.0)
        let a = Float(500.0 * (fx - fy))
        let b = Float(200.0 * (fy - fz))

        return (l, a, b)
    }

    /// Trilinear interpolation to sample colors from the 3D LUT
    private static func sampleLut(r: Float, g: Float, b: Float, size: Int, data: [Float]) -> (r: Float, g: Float, b: Float) {
        let clampedR = max(0, min(r, 1))
        let clampedG = max(0, min(g, 1))
        let clampedB = max(0, min(b, 1))
        let maxIndex = Float(size - 1)

        let x = clampedR * maxIndex
        let y = clampedG * maxIndex
        let z = clampedB * maxIndex

        let xi = Int(floor(x))
        let yi = Int(floor(y))
        let zi = Int(floor(z))

        // Clamp indices
        let clampedXi = min(max(xi, 0), size - 2)
        let clampedYi = min(max(yi, 0), size - 2)
        let clampedZi = min(max(zi, 0), size - 2)

        // Local coordinates (0-1)
        let u = max(0, min(x - Float(clampedXi), 1))
        let v = max(0, min(y - Float(clampedYi), 1))
        let w = max(0, min(z - Float(clampedZi), 1))

        func idx(_ x: Int, _ y: Int, _ z: Int) -> Int {
            (z * size * size + y * size + x) * 3
        }

        func interp(offset: Int) -> Float {
            let c000 = data[idx(clampedXi, clampedYi, clampedZi) + offset]
            let c100 = data[idx(clampedXi + 1, clampedYi, clampedZi) + offset]
            let c010 = data[idx(clampedXi, clampedYi + 1, clampedZi) + offset]
            let c001 = data[idx(clampedXi, clampedYi, clampedZi + 1) + offset]
            let c110 = data[idx(clampedXi + 1, clampedYi + 1, clampedZi) + offset]
            let c101 = data[idx(clampedXi + 1, clampedYi, clampedZi + 1) + offset]
            let c011 = data[idx(clampedXi, clampedYi + 1, clampedZi + 1) + offset]
            let c111 = data[idx(clampedXi + 1, clampedYi + 1, clampedZi + 1) + offset]

            let c00 = c000 * (1 - u) + c100 * u
            let c01 = c001 * (1 - u) + c101 * u
            let c10 = c010 * (1 - u) + c110 * u
            let c11 = c011 * (1 - u) + c111 * u

            let c0 = c00 * (1 - v) + c10 * v
            let c1 = c01 * (1 - v) + c11 * v

            return c0 * (1 - w) + c1 * w
        }

        return (interp(offset: 0), interp(offset: 1), interp(offset: 2))
    }
}
