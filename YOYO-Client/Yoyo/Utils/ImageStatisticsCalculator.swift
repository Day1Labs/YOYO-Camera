import Accelerate
import AVFoundation
import CoreMedia
import UIKit

/// Image statistics result
struct ImageStatistics {
    /// luminance histogram (256 bins)
    let lumaHistogram: [Int]
    /// RGB (can, only)
    let rgbHistogram: (r: [Int], g: [Int], b: [Int])?
    /// average luminance (0-1)
    let averageBrightness: Float
}

/// High-performance image statistics calculator
/// Use vImage and SIMD instructions to operate on memory directly instead of expensive Core Image conversions
enum ImageStatisticsCalculator {
    // MARK: - Public Methods

    /// imagedata
    /// - Parameters:
    ///   - sampleBuffer: cameradata
    ///   - stride: (1, 1)
    ///   - includeRGB: whether RGB
    /// - Returns: result
    static func analyze(from sampleBuffer: CMSampleBuffer, stride: Int = 1, includeRGB: Bool = false) -> ImageStatistics? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var lumaHistogram = Array(repeating: 0, count: 256)
        var rgbHistogram: (r: [Int], g: [Int], b: [Int])?

        // 1. Luma
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            lumaHistogram = calculateYUVLumaHistogram(pixelBuffer: pixelBuffer, step: stride, pixelFormat: pixelFormat)

        case kCVPixelFormatType_32BGRA:
            lumaHistogram = calculateBGRALumaHistogram(pixelBuffer: pixelBuffer, step: stride)

        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            lumaHistogram = calculateYUV10BitLumaHistogram(pixelBuffer: pixelBuffer, step: stride)

        default:
            return nil
        }

        // 2. RGB (ifneed to)
        if includeRGB {
            rgbHistogram = calculateRGBHistogram(pixelBuffer: pixelBuffer, step: stride, pixelFormat: pixelFormat)
        }

        // 3. average luminance
        let averageBrightness = calculateAverageBrightness(from: lumaHistogram)

        return ImageStatistics(
            lumaHistogram: lumaHistogram,
            rgbHistogram: rgbHistogram,
            averageBrightness: averageBrightness
        )
    }

    // MARK: - Private Calculation Methods

    private static func calculateYUVLumaHistogram(pixelBuffer: CVPixelBuffer, step: Int, pixelFormat: OSType) -> [Int] {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return [] }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let stepX = max(1, step)
        let stepY = max(1, step)

        if stepX == 1, stepY == 1 {
            // : use vImage
            var buffer = vImage_Buffer(data: baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
            var histogramBins = [vImagePixelCount](repeating: 0, count: 256)

            histogramBins.withUnsafeMutableBufferPointer { ptr in
                guard let baseAddress = ptr.baseAddress else { return }
                vImageHistogramCalculation_Planar8(&buffer, baseAddress, 0)
            }

            if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
                // Video Range (16-235) -> Full Range (0-255)
                return convertVideoRangeToFullRange(histogramBins: histogramBins)
            } else {
                return histogramBins.map { Int($0) }
            }
        } else {
            // : manual
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            let isVideoRange = (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            let scale: Float = 255.0 / 219.0

            // use Float, Int
            var floatHist = Array(repeating: Float(0), count: 256)

            for y in stride(from: 0, to: height, by: stepY) {
                let rowStart = y * rowBytes
                for x in stride(from: 0, to: width, by: stepX) {
                    let v8 = Int(ptr[rowStart + x])
                    if isVideoRange {
                        let pos = (Float(v8) - 16.0) * scale
                        if pos <= 0 {
                            floatHist[0] += 1.0
                        } else if pos >= 255 {
                            floatHist[255] += 1.0
                        } else {
                            let idx = Int(pos)
                            let w = pos - Float(idx)
                            floatHist[idx] += 1.0 - w
                            floatHist[idx + 1] += w
                        }
                    } else {
                        floatHist[v8] += 1.0
                    }
                }
            }
            return floatHist.map { Int($0) }
        }
    }

    private static func calculateBGRALumaHistogram(pixelBuffer: CVPixelBuffer, step: Int) -> [Int] {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let stepX = max(1, step)
        let stepY = max(1, step)

        if stepX == 1, stepY == 1 {
            // : vImage +
            var srcBuffer = vImage_Buffer(data: baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
            var destBuffer = vImage_Buffer()
            // initialization buffer
            guard vImageBuffer_Init(&destBuffer, vImagePixelCount(height), vImagePixelCount(width), 8, 0) == kvImageNoError else { return [] }
            defer { free(destBuffer.data) }

            // Rec.709 coefficients
            let redCoeff: Float = 0.2126
            let greenCoeff: Float = 0.7152
            let blueCoeff: Float = 0.0722
            let divisor: Int32 = 0x1000

            let matrix = [
                Int16(blueCoeff * Float(divisor)),
                Int16(greenCoeff * Float(divisor)),
                Int16(redCoeff * Float(divisor)),
                0,
            ]

            vImageMatrixMultiply_ARGB8888ToPlanar8(&srcBuffer, &destBuffer, matrix, divisor, nil, 0, 0)

            var histogramBins = [vImagePixelCount](repeating: 0, count: 256)
            histogramBins.withUnsafeMutableBufferPointer { ptr in
                guard let baseAddress = ptr.baseAddress else { return }
                vImageHistogramCalculation_Planar8(&destBuffer, baseAddress, 0)
            }
            return histogramBins.map { Int($0) }
        } else {
            // Downsampling
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            let redCoeff: Float = 0.2126
            let greenCoeff: Float = 0.7152
            let blueCoeff: Float = 0.0722
            var histogram = Array(repeating: 0, count: 256)

            for y in stride(from: 0, to: height, by: stepY) {
                let rowStart = y * rowBytes
                for x in stride(from: 0, to: width, by: stepX) {
                    let offset = rowStart + x * 4
                    let b = Float(ptr[offset])
                    let g = Float(ptr[offset + 1])
                    let r = Float(ptr[offset + 2])
                    let luma = redCoeff * r + greenCoeff * g + blueCoeff * b
                    let val = clampTo8bit(luma)
                    histogram[val] += 1
                }
            }
            return histogram
        }
    }

    private static func calculateYUV10BitLumaHistogram(pixelBuffer: CVPixelBuffer, step: Int) -> [Int] {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return [] }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let ptr = baseAddress.assumingMemoryBound(to: UInt16.self)
        let yStride = rowBytes / 2
        let stepX = max(1, step)
        let stepY = max(1, step)

        var floatHist = Array(repeating: Float(0), count: 256)

        // 10-bit Video Range (64-940) -> 8-bit Full Range (0-255)
        // Range = 940 - 64 = 876

        for y in stride(from: 0, to: height, by: stepY) {
            let rowStart = y * yStride
            for x in stride(from: 0, to: width, by: stepX) {
                // MSB aligned: top 10 bits are data.
                // Shift right by 6 to get 0-1023 value.
                let val10 = Int(ptr[rowStart + x] >> 6)

                let mappedIndex: Int
                if val10 <= 64 { mappedIndex = 0 }
                else if val10 >= 940 { mappedIndex = 255 }
                else { mappedIndex = (val10 - 64) * 255 / 876 }

                floatHist[mappedIndex] += 1.0
            }
        }
        return floatHist.map { Int($0) }
    }

    private static func calculateRGBHistogram(pixelBuffer: CVPixelBuffer, step: Int, pixelFormat: OSType) -> (r: [Int], g: [Int], b: [Int])? {
        // implement: onlysupportmode, because RGB vImage
        // here HistogramView logic

        var newR = Array(repeating: 0, count: 256)
        var newG = Array(repeating: 0, count: 256)
        var newB = Array(repeating: 0, count: 256)

        let stepX = max(1, step)
        let stepY = max(1, step)

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return nil }
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let yRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let uvRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

            let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
            let uvPtr = uvBase.assumingMemoryBound(to: UInt8.self)

            let isFullRange = (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)

            for y in stride(from: 0, to: height, by: stepY) {
                let yRowStart = y * yRowBytes
                let uvRowStart = (y / 2) * uvRowBytes
                for x in stride(from: 0, to: width, by: stepX) {
                    let yVal = Int(yPtr[yRowStart + x])
                    let uvX = (x / 2) * 2
                    let cbVal = Int(uvPtr[uvRowStart + uvX])
                    let crVal = Int(uvPtr[uvRowStart + uvX + 1])

                    let r8, g8, b8: Int
                    if isFullRange {
                        let Y = Float(yVal)
                        let Cb = Float(cbVal) - 128.0
                        let Cr = Float(crVal) - 128.0
                        r8 = clampTo8bit(Y + 1.5748 * Cr)
                        let gPart1 = Y
                        let gPart2 = 0.1873 * Cb
                        let gPart3 = 0.4681 * Cr
                        g8 = clampTo8bit(gPart1 - gPart2 - gPart3)
                        b8 = clampTo8bit(Y + 1.8556 * Cb)
                    } else {
                        let C = Float(yVal - 16)
                        let D = Float(cbVal - 128)
                        let E = Float(crVal - 128)
                        r8 = clampTo8bit(1.164 * C + 1.793 * E)
                        let gPart1 = 1.164 * C
                        let gPart2 = 0.213 * D
                        let gPart3 = 0.533 * E
                        g8 = clampTo8bit(gPart1 - gPart2 - gPart3)
                        b8 = clampTo8bit(1.164 * C + 2.112 * D)
                    }
                    newR[r8] += 1
                    newG[g8] += 1
                    newB[b8] += 1
                }
            }

        case kCVPixelFormatType_32BGRA:
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

            for y in stride(from: 0, to: height, by: stepY) {
                let rowStart = y * rowBytes
                for x in stride(from: 0, to: width, by: stepX) {
                    let offset = rowStart + x * 4
                    let b = Int(ptr[offset])
                    let g = Int(ptr[offset + 1])
                    let r = Int(ptr[offset + 2])
                    newR[r] += 1
                    newG[g] += 1
                    newB[b] += 1
                }
            }

        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            // 10-bit RGB
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
                  let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return nil }
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let yRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let uvRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

            let yPtr = yBase.assumingMemoryBound(to: UInt16.self)
            let uvPtr = uvBase.assumingMemoryBound(to: UInt16.self)
            let yStride = yRowBytes / 2
            let uvStride = uvRowBytes / 2

            for y in stride(from: 0, to: height, by: stepY) {
                let yRowStart = y * yStride
                let uvRowStart = (y / 2) * uvStride
                for x in stride(from: 0, to: width, by: stepX) {
                    let y8 = Int(yPtr[yRowStart + x] >> 2)
                    let uvX16 = (x / 2) * 2
                    let cb8 = Int(uvPtr[uvRowStart + uvX16] >> 2)
                    let cr8 = Int(uvPtr[uvRowStart + uvX16 + 1] >> 2)

                    let C = Float(max(0, y8 - 16))
                    let D = Float(cb8 - 128)
                    let E = Float(cr8 - 128)
                    let r8 = clampTo8bit(1.164 * C + 1.793 * E)
                    let gPart1 = 1.164 * C
                    let gPart2 = 0.213 * D
                    let gPart3 = 0.533 * E
                    let g8 = clampTo8bit(gPart1 - gPart2 - gPart3)
                    let b8 = clampTo8bit(1.164 * C + 2.112 * D)
                    newR[r8] += 1
                    newG[g8] += 1
                    newB[b8] += 1
                }
            }

        default:
            return nil
        }

        return (newR, newG, newB)
    }

    // MARK: - Helper Methods

    private static func convertVideoRangeToFullRange(histogramBins: [vImagePixelCount]) -> [Int] {
        var newHistogram = Array(repeating: Float(0), count: 256)
        let scale: Float = 255.0 / 219.0

        for i in 0 ..< 256 {
            let count = Float(histogramBins[i])
            if count > 0 {
                let pos = (Float(i) - 16.0) * scale
                if pos <= 0 {
                    newHistogram[0] += count
                } else if pos >= 255 {
                    newHistogram[255] += count
                } else {
                    let idx = Int(pos)
                    let w = pos - Float(idx)
                    newHistogram[idx] += count * (1.0 - w)
                    newHistogram[idx + 1] += count * w
                }
            }
        }
        return newHistogram.map { Int($0) }
    }

    private static func calculateAverageBrightness(from histogram: [Int]) -> Float {
        var totalBrightness: Float = 0
        var totalPixels = 0

        for (i, count) in histogram.enumerated() {
            totalBrightness += Float(i) * Float(count)
            totalPixels += count
        }

        if totalPixels == 0 { return 0.0 }
        return (totalBrightness / Float(totalPixels)) / 255.0
    }

    private static func clampTo8bit(_ v: Float) -> Int {
        let iv = Int(v.rounded())
        return max(0, min(255, iv))
    }
}
