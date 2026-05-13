import Accelerate
import AVFoundation
import CoreImage
import Vision

/// Brightness calculator - focuses on numerical image brightness, contrast, and histogram calculations
/// Does not include lighting condition judgment; LightingAnalyzer handles semantic analysis
enum BrightnessCalculator {
    // MARK: - main methods

    /// Calculate average brightness from a CMSampleBuffer
    static func calculateAverageBrightness(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return 0.5 // default medium brightness
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        return calculateAverageBrightness(ciImage: ciImage)
    }

    /// Calculate average brightness from a CIImage
    static func calculateAverageBrightness(ciImage: CIImage) -> Float {
        // Use Core Image's area-average filter
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return calculateBrightnessManually(ciImage: ciImage)
        }

        // set the input image and sampling region
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return calculateBrightnessManually(ciImage: ciImage)
        }

        // render to a 1x1 pixel image to get the average value
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var pixel: [UInt8] = [0, 0, 0, 0]

        context.render(outputImage, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        // Use the ITU-R BT.709 standard brightness calculation
        let r = Float(pixel[0]) / 255.0
        let g = Float(pixel[1]) / 255.0
        let b = Float(pixel[2]) / 255.0

        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Calculate image contrast
    static func calculateContrast(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return 0.5
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        return calculateContrast(ciImage: ciImage)
    }

    /// Calculate contrast from a CIImage
    static func calculateContrast(ciImage: CIImage) -> Float {
        // downscale the image to improve performance
        let scaledImage = scaleImageForAnalysis(ciImage)

        // get the brightness value array
        guard let brightnessValues = getBrightnessValues(from: scaledImage) else {
            return 0.5
        }

        // calculate standard deviation as the contrast metric
        let mean = brightnessValues.reduce(0, +) / Float(brightnessValues.count)
        let variance = brightnessValues.map { pow($0 - mean, 2) }.reduce(0, +) / Float(brightnessValues.count)
        let standardDeviation = sqrt(variance)

        // map standard deviation to the 0-1 range
        return min(standardDeviation * 4.0, 1.0)
    }

    /// Calculate contrast (based on histogram)
    static func calculateContrast(from histogram: [Int], mean: Float) -> Float {
        let totalPixels = histogram.reduce(0, +)
        if totalPixels == 0 { return 0.5 }

        var variance: Float = 0
        for (i, count) in histogram.enumerated() {
            let val = Float(i) / 255.0
            let diff = val - mean
            variance += diff * diff * Float(count)
        }
        variance /= Float(totalPixels)
        let standardDeviation = sqrt(variance)

        // map standard deviation to the 0-1 range
        return min(standardDeviation * 4.0, 1.0)
    }

    /// Analyze histogram distribution
    static func analyzeHistogram(from sampleBuffer: CMSampleBuffer) -> HistogramAnalysis {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return HistogramAnalysis.defaultAnalysis()
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        return analyzeHistogram(ciImage: ciImage)
    }

    /// Analyze histogram distribution (based on a precomputed histogram)
    static func analyzeHistogram(from histogram: [Int]) -> HistogramAnalysis {
        let binCount = histogram.count
        let totalPixels = histogram.reduce(0, +)

        if totalPixels == 0 { return HistogramAnalysis.defaultAnalysis() }

        // calculate the peak position
        let maxBin = histogram.enumerated().max { $0.element < $1.element }?.offset ?? 128
        let peakBrightness = Float(maxBin) / Float(binCount - 1)

        // calculate the shadow, midtone, and highlight ratios
        let shadowThreshold = binCount / 4 // 25%
        let highlightThreshold = binCount * 3 / 4 // 75%

        let shadowPixels = histogram[0 ..< shadowThreshold].reduce(0, +)
        let highlightPixels = histogram[highlightThreshold ..< binCount].reduce(0, +)
        let midtonePixels = totalPixels - shadowPixels - highlightPixels

        let shadowRatio = Float(shadowPixels) / Float(totalPixels)
        let midtoneRatio = Float(midtonePixels) / Float(totalPixels)
        let highlightRatio = Float(highlightPixels) / Float(totalPixels)

        // detect overexposure or underexposure
        let isOverexposed = highlightRatio > 0.15 && histogram[binCount - 1] > totalPixels / 100
        let isUnderexposed = shadowRatio > 0.25 && histogram[0] > totalPixels / 100

        return HistogramAnalysis(
            shadowRatio: shadowRatio,
            midtoneRatio: midtoneRatio,
            highlightRatio: highlightRatio,
            peakBrightness: peakBrightness,
            isOverexposed: isOverexposed,
            isUnderexposed: isUnderexposed,
            dynamicRange: calculateDynamicRange(histogram: histogram)
        )
    }

    /// Analyze the histogram from a CIImage
    static func analyzeHistogram(ciImage: CIImage) -> HistogramAnalysis {
        guard let brightnessValues = getBrightnessValues(from: scaleImageForAnalysis(ciImage)) else {
            return HistogramAnalysis.defaultAnalysis()
        }

        // create histogram bins
        let binCount = LightingThresholds.Performance.histogramBinCount
        var histogram = Array(repeating: 0, count: binCount)

        for brightness in brightnessValues {
            let binIndex = min(Int(brightness * Float(binCount - 1)), binCount - 1)
            histogram[binIndex] += 1
        }

        // analyze histogram features
        let totalPixels = brightnessValues.count

        // calculate the peak position
        let maxBin = histogram.enumerated().max { $0.element < $1.element }?.offset ?? 128
        let peakBrightness = Float(maxBin) / Float(binCount - 1)

        // calculate the shadow, midtone, and highlight ratios
        let shadowThreshold = binCount / 4 // 25%
        let highlightThreshold = binCount * 3 / 4 // 75%

        let shadowPixels = histogram[0 ..< shadowThreshold].reduce(0, +)
        let highlightPixels = histogram[highlightThreshold ..< binCount].reduce(0, +)
        let midtonePixels = totalPixels - shadowPixels - highlightPixels

        let shadowRatio = Float(shadowPixels) / Float(totalPixels)
        let midtoneRatio = Float(midtonePixels) / Float(totalPixels)
        let highlightRatio = Float(highlightPixels) / Float(totalPixels)

        // detect overexposure or underexposure
        let isOverexposed = highlightRatio > 0.15 && histogram[binCount - 1] > totalPixels / 100
        let isUnderexposed = shadowRatio > 0.25 && histogram[0] > totalPixels / 100

        return HistogramAnalysis(
            shadowRatio: shadowRatio,
            midtoneRatio: midtoneRatio,
            highlightRatio: highlightRatio,
            peakBrightness: peakBrightness,
            isOverexposed: isOverexposed,
            isUnderexposed: isUnderexposed,
            dynamicRange: calculateDynamicRange(histogram: histogram)
        )
    }

    /// Calculate dynamic range
    private static func calculateDynamicRange(histogram: [Int]) -> Float {
        // find the effective darkest and brightest pixel positions(ignoring rare outliers)
        let totalPixels = histogram.reduce(0, +)
        let threshold = Int(Float(totalPixels) * LightingThresholds.Performance.dynamicRangeThreshold)

        var darkestBin = 0
        var brightestBin = histogram.count - 1

        // search from the dark end
        for i in 0 ..< histogram.count {
            if histogram[i] > threshold {
                darkestBin = i
                break
            }
        }

        // search from the bright end
        for i in stride(from: histogram.count - 1, through: 0, by: -1) {
            if histogram[i] > threshold {
                brightestBin = i
                break
            }
        }

        return Float(brightestBin - darkestBin) / Float(histogram.count - 1)
    }

    /// Get the basic brightness analysis result (without lighting condition judgment)
    static func getBasicBrightnessAnalysis(from sampleBuffer: CMSampleBuffer) -> BasicBrightnessAnalysis {
        // prefer the high-performance calculator
        if let stats = ImageStatisticsCalculator.analyze(from: sampleBuffer, stride: 4) {
            let averageBrightness = stats.averageBrightness
            let histogramAnalysis = analyzeHistogram(from: stats.lumaHistogram)
            let contrast = calculateContrast(from: stats.lumaHistogram, mean: averageBrightness)

            return BasicBrightnessAnalysis(
                averageBrightness: averageBrightness,
                contrast: contrast,
                histogram: histogramAnalysis
            )
        }

        let averageBrightness = calculateAverageBrightness(from: sampleBuffer)
        let contrast = calculateContrast(from: sampleBuffer)
        let histogram = analyzeHistogram(from: sampleBuffer)

        return BasicBrightnessAnalysis(
            averageBrightness: averageBrightness,
            contrast: contrast,
            histogram: histogram
        )
    }

    // MARK: - private helper methods

    /// Manually calculate brightness (fallback method)
    private static func calculateBrightnessManually(ciImage: CIImage) -> Float {
        guard let brightnessValues = getBrightnessValues(from: scaleImageForAnalysis(ciImage)) else {
            return 0.5
        }

        return brightnessValues.reduce(0, +) / Float(brightnessValues.count)
    }

    /// Scale the image to improve analysis performance
    private static func scaleImageForAnalysis(_ ciImage: CIImage) -> CIImage {
        let targetSize = LightingThresholds.Performance.analysisImageSize
        let originalSize = ciImage.extent.size

        let scale = min(targetSize / originalSize.width, targetSize / originalSize.height)

        if scale < 1.0 {
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            return ciImage.transformed(by: transform)
        }

        return ciImage
    }

    /// Get the brightness value array from the image
    private static func getBrightnessValues(from ciImage: CIImage) -> [Float]? {
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let extent = ciImage.extent

        guard extent.width > 0, extent.height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = Int(extent.width) * bytesPerPixel
        let totalBytes = Int(extent.height) * bytesPerRow

        var pixelData = Data(count: totalBytes)

        let success = pixelData.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }

            context.render(ciImage, toBitmap: baseAddress, rowBytes: bytesPerRow,
                           bounds: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return true
        }

        guard success else { return nil }

        var brightnessValues: [Float] = []
        brightnessValues.reserveCapacity(Int(extent.width * extent.height))

        pixelData.withUnsafeBytes { bytes in
            let uint8Ptr = bytes.bindMemory(to: UInt8.self)

            for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
                let r = Float(uint8Ptr[i]) / 255.0
                let g = Float(uint8Ptr[i + 1]) / 255.0
                let b = Float(uint8Ptr[i + 2]) / 255.0

                // Use the ITU-R BT.709 standard brightness calculation
                let brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
                brightnessValues.append(brightness)
            }
        }

        return brightnessValues
    }
}

// MARK: - supporting types

/// Basic brightness analysis result (numerical calculations only, without semantic judgments)
struct BasicBrightnessAnalysis {
    let averageBrightness: Float
    let contrast: Float
    let histogram: HistogramAnalysis
}

/// Histogram analysis result
struct HistogramAnalysis {
    let shadowRatio: Float // shadow ratio
    let midtoneRatio: Float // midtone ratio
    let highlightRatio: Float // highlight area ratio
    let peakBrightness: Float // peak brightness position
    let isOverexposed: Bool // whether it is overexposed
    let isUnderexposed: Bool // whether it is underexposed
    let dynamicRange: Float // Dynamic range (0-1)

    static func defaultAnalysis() -> HistogramAnalysis {
        HistogramAnalysis(
            shadowRatio: 0.33,
            midtoneRatio: 0.33,
            highlightRatio: 0.33,
            peakBrightness: 0.5,
            isOverexposed: false,
            isUnderexposed: false,
            dynamicRange: 0.8
        )
    }
}
