@preconcurrency import AVFoundation

/// formatresult
struct FormatSelectionResult {
    let format: AVCaptureDevice.Format
    let actualResolution: CMVideoDimensions
    let actualFrameRate: Int32
    let isExactMatch: Bool
}

/// cameraformat
/// cameraformat()
final class CameraFormatSelector {
    static let shared = CameraFormatSelector()

    private init() {}

    /// format
    /// - Parameters:
    ///   - device: device
    ///   - desiredResolution:
    ///   - desiredFrameRate:
    /// - Returns: formatresult
    func selectBestFormat(for device: AVCaptureDevice,
                          desiredResolution: CMVideoDimensions,
                          desiredFrameRate: Int32) -> FormatSelectionResult?
    {
        print("🔍 [CameraFormatSelector] 开始选择格式: \(desiredResolution.width)x\(desiredResolution.height)@\(desiredFrameRate)fps")

        let formats = device.formats

        // 1. format
        if let exactMatch = findExactMatch(formats: formats,
                                           desiredResolution: desiredResolution,
                                           desiredFrameRate: desiredFrameRate)
        {
            print("✅ [CameraFormatSelector] 找到完全匹配的格式")
            return FormatSelectionResult(format: exactMatch,
                                         actualResolution: desiredResolution,
                                         actualFrameRate: desiredFrameRate,
                                         isExactMatch: true)
        }

        // 2. supporttarget frame rateformat
        if let sameResolutionResult = findSameResolutionBestFrameRate(formats: formats,
                                                                      desiredResolution: desiredResolution,
                                                                      desiredFrameRate: desiredFrameRate)
        {
            print("⚠️ [CameraFormatSelector] 相同分辨率，保持帧率: \(desiredFrameRate)fps")
            return sameResolutionResult
        } else {
            print("ℹ️ [CameraFormatSelector] 相同分辨率下无设备支持 \(desiredFrameRate)fps")
        }

        // 3. supporttarget frame rate
        if let bestAlternative = findBestAlternativeFormat(formats: formats,
                                                           desiredFrameRate: desiredFrameRate)
        {
            print("⚠️ [CameraFormatSelector] 使用替代格式: \(bestAlternative.actualResolution.width)x\(bestAlternative.actualResolution.height)@\(bestAlternative.actualFrameRate)fps")
            return bestAlternative
        }

        print("❌ [CameraFormatSelector] 未找到合适的格式")
        return nil
    }

    // MARK: - Private Methods

    /// format
    private func findExactMatch(formats: [AVCaptureDevice.Format],
                                desiredResolution: CMVideoDimensions,
                                desiredFrameRate: Int32) -> AVCaptureDevice.Format?
    {
        formats.first { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supportsResolution = dimensions.width == desiredResolution.width &&
                dimensions.height == desiredResolution.height

            guard supportsResolution else { return false }

            return format.videoSupportedFrameRateRanges.contains { range in
                Double(desiredFrameRate) >= range.minFrameRate &&
                    Double(desiredFrameRate) <= range.maxFrameRate
            }
        }
    }

    /// supporttarget frame rateformat
    private func findSameResolutionBestFrameRate(formats: [AVCaptureDevice.Format],
                                                 desiredResolution: CMVideoDimensions,
                                                 desiredFrameRate: Int32) -> FormatSelectionResult?
    {
        let desired = Double(desiredFrameRate)
        let sameResolutionFormats = formats.compactMap { format -> (format: AVCaptureDevice.Format, maxHeadroom: Double)? in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dimensions.width == desiredResolution.width,
                  dimensions.height == desiredResolution.height else { return nil }

            guard let supportingRange = format.videoSupportedFrameRateRanges
                .filter({ desired >= $0.minFrameRate && desired <= $0.maxFrameRate })
                .max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { return nil }

            return (format, supportingRange.maxFrameRate)
        }

        guard let bestCandidate = sameResolutionFormats.max(by: { $0.maxHeadroom < $1.maxHeadroom }) else {
            return nil
        }

        return FormatSelectionResult(format: bestCandidate.format,
                                     actualResolution: desiredResolution,
                                     actualFrameRate: desiredFrameRate,
                                     isExactMatch: false)
    }

    /// format
    private func findBestAlternativeFormat(formats: [AVCaptureDevice.Format],
                                           desiredFrameRate: Int32) -> FormatSelectionResult?
    {
        let candidates: [(format: AVCaptureDevice.Format, dimensions: CMVideoDimensions, frameRate: Double)] =
            formats.compactMap { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

                // supporttarget frame rateformat
                if format.videoSupportedFrameRateRanges.first(where: { range in
                    Double(desiredFrameRate) >= range.minFrameRate && Double(desiredFrameRate) <= range.maxFrameRate
                }) != nil {
                    return (format, dimensions, Double(desiredFrameRate))
                }

                // ifnot supporttarget frame rate, usemaximumsupport
                if let maxFps = getMaxFrameRate(for: format, minFrameRate: Double(desiredFrameRate)),
                   maxFps > 0
                {
                    return (format, dimensions, maxFps)
                }

                return nil
            }

        // ,
        let bestCandidate = candidates.max { candidate1, candidate2 in
            let pixels1 = Int(candidate1.dimensions.width) * Int(candidate1.dimensions.height)
            let pixels2 = Int(candidate2.dimensions.width) * Int(candidate2.dimensions.height)

            if pixels1 == pixels2 {
                return candidate1.frameRate < candidate2.frameRate
            }
            return pixels1 < pixels2
        }

        guard let candidate = bestCandidate else { return nil }

        return FormatSelectionResult(
            format: candidate.format,
            actualResolution: candidate.dimensions,
            actualFrameRate: Int32(candidate.frameRate),
            isExactMatch: false
        )
    }

    /// getformatsupportmaximum
    private func getMaxFrameRate(for format: AVCaptureDevice.Format, minFrameRate: Double) -> Double? {
        let ranges = format.videoSupportedFrameRateRanges
        if let matching = ranges
            .filter({ $0.maxFrameRate >= minFrameRate })
            .map(\.maxFrameRate)
            .max()
        {
            return matching
        }

        return ranges.map(\.maxFrameRate).max()
    }
}
