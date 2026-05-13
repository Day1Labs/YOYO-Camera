import Accelerate
import CoreImage
import UIKit
import Vision

/// Color analyzer - extracts dominant colors and color information from images
/// Uses histogram statistics instead of K-Means to provide deterministic results and better performance.
/// Built-in temporal smoothing helps stabilize automation triggers.
final class ColorAnalyzer {
    /// Singleton instance (used to maintain smoothing state)
    static let shared = ColorAnalyzer()

    /// Reuse CIContext to improve performance
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// History cache (used for smoothing)
    private var historyBuffer: [[UIColor]] = []
    private let historyCapacity = 4 // Cache the last 4 frames

    // MARK: - public static APIs (compatible with legacy code)

    /// Analyze dominant colors from a CMSampleBuffer
    static func analyzeColors(from sampleBuffer: CMSampleBuffer, maxColors: Int = 5) async -> [UIColor] {
        await shared.analyze(from: sampleBuffer, maxColors: maxColors)
    }

    /// Extract dominant colors from a CIImage
    static func extractColors(from ciImage: CIImage, maxColors: Int = 5) async -> [UIColor] {
        await shared.analyze(from: ciImage, maxColors: maxColors)
    }

    // MARK: - instance methods

    func analyze(from sampleBuffer: CMSampleBuffer, maxColors: Int) async -> [UIColor] {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return [] }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        return await analyze(from: ciImage, maxColors: maxColors)
    }

    func analyze(from ciImage: CIImage, maxColors: Int) async -> [UIColor] {
        // 1. preprocess: shrink significantly (50x50 enough to analyze dominant colors while being very fast)
        let scaledImage = scaleImage(ciImage, targetSize: 50)

        // 2. get pixel data
        guard let pixels = getPixels(from: scaledImage) else { return [] }

        // 3. histogram statistics (deterministic algorithm)
        let currentColors = computeHistogram(pixels: pixels, maxColors: maxColors)

        // 4. temporal smoothing
        return stabilize(currentColors)
    }

    // MARK: - core algorithm (histogram statistics)

    private func computeHistogram(pixels: [SIMD3<Float>], maxColors: Int) -> [UIColor] {
        // HSB bucket statistics
        // Hue: 0-360, split into 24 buckets (15 degrees each)
        // also count separately grayscale/black/white

        var bins = Array(repeating: (count: 0, r: Float(0), g: Float(0), b: Float(0)), count: 24)
        var grayCount = 0
        var graySum = SIMD3<Float>(0, 0, 0)

        for pixel in pixels {
            let r = pixel.x
            let g = pixel.y
            let b = pixel.z

            // simple RGB -> HSB
            let maxVal = max(r, max(g, b))
            let minVal = min(r, min(g, b))
            let delta = maxVal - minVal

            // filter very dark or very bright pixels (background noise)
            if maxVal < 0.15 || minVal > 0.95 { continue }

            // low saturation -> classify as grayscale
            let saturation = maxVal == 0 ? 0 : delta / maxVal
            if saturation < 0.15 {
                grayCount += 1
                graySum += pixel
                continue
            }

            // calculate hue
            var hue: Float = 0
            if delta > 0 {
                if maxVal == r {
                    hue = (g - b) / delta + (g < b ? 6 : 0)
                } else if maxVal == g {
                    hue = (b - r) / delta + 2
                } else {
                    hue = (r - g) / delta + 4
                }
                hue /= 6.0
            }

            // place into the bucket
            let binIndex = Int(hue * Float(bins.count)) % bins.count
            bins[binIndex].count += 1
            bins[binIndex].r += r
            bins[binIndex].g += g
            bins[binIndex].b += b
        }

        // organize results
        var candidates: [(color: UIColor, count: Int)] = []

        // add color candidates
        for bin in bins where bin.count > 0 {
            let color = UIColor(
                red: CGFloat(bin.r / Float(bin.count)),
                green: CGFloat(bin.g / Float(bin.count)),
                blue: CGFloat(bin.b / Float(bin.count)),
                alpha: 1.0
            )
            candidates.append((color, bin.count))
        }

        // add grayscale candidates (if the ratio is large enough)
        if grayCount > 0 {
            let color = UIColor(
                red: CGFloat(graySum.x / Float(grayCount)),
                green: CGFloat(graySum.y / Float(grayCount)),
                blue: CGFloat(graySum.z / Float(grayCount)),
                alpha: 1.0
            )
            candidates.append((color, grayCount))
        }

        // sort and trim
        candidates.sort { $0.count > $1.count }
        return candidates.prefix(maxColors).map(\.color)
    }

    // MARK: - Helper methods

    private func stabilize(_ newColors: [UIColor]) -> [UIColor] {
        historyBuffer.append(newColors)
        if historyBuffer.count > historyCapacity {
            historyBuffer.removeFirst()
        }

        // simple smoothing: if history is insufficient, return directly
        if historyBuffer.count < 2 { return newColors }

        // voting mechanism: count the most frequent color in recent frames
        // Simplified handling: if the current primary dominant color also existed in the previous frame (similar), prefer the previous frame's color value to avoid minor flicker
        // otherwise use the new color

        guard let firstNew = newColors.first, let lastFrame = historyBuffer.dropLast().last else {
            return newColors
        }

        var stabilizedResult = newColors

        // try to stabilize the primary dominant color
        if let similarInLastFrame = lastFrame.first(where: { colorsSimilar($0, firstNew, threshold: 0.1) }) {
            stabilizedResult[0] = similarInLastFrame
        }

        return stabilizedResult
    }

    private func scaleImage(_ image: CIImage, targetSize: CGFloat) -> CIImage {
        let scale = targetSize / max(image.extent.width, image.extent.height)
        if scale >= 1 { return image }
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func getPixels(from image: CIImage) -> [SIMD3<Float>]? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = Int(extent.width) * bytesPerPixel
        let totalBytes = Int(extent.height) * bytesPerRow

        var pixelData = Data(count: totalBytes)

        let success = pixelData.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }

            context.render(image, toBitmap: baseAddress, rowBytes: bytesPerRow,
                           bounds: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return true
        }

        guard success else { return nil }

        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(Int(extent.width * extent.height))

        pixelData.withUnsafeBytes { bytes in
            let uint8Ptr = bytes.bindMemory(to: UInt8.self)

            for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
                let r = Float(uint8Ptr[i]) / 255.0
                let g = Float(uint8Ptr[i + 1]) / 255.0
                let b = Float(uint8Ptr[i + 2]) / 255.0
                pixels.append(SIMD3<Float>(r, g, b))
            }
        }

        return pixels
    }

    private func colorsSimilar(_ c1: UIColor, _ c2: UIColor, threshold: CGFloat) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let dist = sqrt(pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2))
        return dist < threshold
    }

    /// calculate image color temperature(warm/cool tones)
    static func calculateColorTemperature(from colors: [UIColor]) -> ColorTemperature {
        var warmScore: Float = 0
        var coolScore: Float = 0

        for color in colors {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: nil)

            let r = Float(red)
            let g = Float(green)
            let b = Float(blue)

            // warm-tone detection(red, orange, and yellow tendencies)
            if r > g, r > b {
                warmScore += r - max(g, b)
            }
            if r > 0.5, g > 0.3, b < 0.3 { // orange tendency
                warmScore += 0.3
            }
            if r > 0.7, g > 0.7, b < 0.3 { // yellow tendency
                warmScore += 0.2
            }

            // cool-tone detection(blue, cyan, and purple tendencies)
            if b > r, b > g {
                coolScore += b - max(r, g)
            }
            if b > 0.5, g > 0.3, r < 0.3 { // cyan tendency
                coolScore += 0.3
            }
            if b > 0.5, r > 0.3, g < 0.3 { // purple tendency
                coolScore += 0.2
            }
        }

        let ratio = coolScore / (warmScore + coolScore + 0.001) // avoid division by zero

        if ratio > 0.6 {
            return .cool
        } else if ratio < 0.4 {
            return .warm
        } else {
            return .neutral
        }
    }

    /// calculate image saturation
    static func calculateSaturation(from colors: [UIColor]) -> Float {
        var totalSaturation: Float = 0

        for color in colors {
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            totalSaturation += Float(saturation)
        }

        return colors.isEmpty ? 0 : totalSaturation / Float(colors.count)
    }
}

// MARK: - supporting types

/// color temperature type
enum ColorTemperature: String, Codable, CaseIterable {
    case warm // warm tone
    case cool // cool tone
    case neutral // neutral

    var displayName: String {
        switch self {
        case .warm: return String.colorTempWarm.localized
        case .cool: return String.colorTempCool.localized
        case .neutral: return String.colorTempNeutral.localized
        }
    }
}

/// color analysis result
struct ColorAnalysisResult {
    let dominantColors: [UIColor]
    let temperature: ColorTemperature
    let averageSaturation: Float
    let averageBrightness: Float
}

// MARK: - extension methods

extension ColorAnalyzer {
    /// get the full color analysis result
    static func getCompleteColorAnalysis(from sampleBuffer: CMSampleBuffer) async -> ColorAnalysisResult {
        let dominantColors = await analyzeColors(from: sampleBuffer)
        let temperature = calculateColorTemperature(from: dominantColors)
        let saturation = calculateSaturation(from: dominantColors)

        // calculate average brightness
        var totalBrightness: Float = 0
        for color in dominantColors {
            var brightness: CGFloat = 0
            color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
            totalBrightness += Float(brightness)
        }
        let averageBrightness = dominantColors.isEmpty ? 0 : totalBrightness / Float(dominantColors.count)

        return ColorAnalysisResult(
            dominantColors: dominantColors,
            temperature: temperature,
            averageSaturation: saturation,
            averageBrightness: averageBrightness
        )
    }
}
