import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit // For UIDeviceOrientation

// MARK: - Raw Development (CIRAWFilter Integration)

extension FilterManager {
    struct RawDevelopmentConfig {
        var boostAmount: Float = 1.0
        var shadowBias: Float = 0.0
        var sharpnessAmount: Float = 0.4
        var localToneMapAmount: Float = 1.0 // Enabled by default for better dynamic range
        var colorNoiseReductionAmount: Float = 0.5
        var luminanceNoiseReductionAmount: Float = 0.4
        var moireReductionAmount: Float = 0.5
        var contrastAmount: Float? // nil means use the default
        var detailAmount: Float?
    }

    /// Get the Raw decoding configuration corresponding to the current film preset
    private func getCurrentRawConfig() -> RawDevelopmentConfig {
        switch filmPresetID {
        case FilmPreset.kodak5219.id: // Leica: solid mid-tones, high sharpness, high highlights
            return RawDevelopmentConfig(
                boostAmount: 0.85,
                shadowBias: -0.15, // Deepen shadows
                sharpnessAmount: 0.7,
                localToneMapAmount: 0.8,
                colorNoiseReductionAmount: 0.5,
                contrastAmount: 1.1
            )
        case FilmPreset.agfaVista400.id: // GR: High contrast, tough, retain noise
            return RawDevelopmentConfig(
                boostAmount: 1.05,
                shadowBias: 0.0, // 0.5 -> 0.0: Removes shadow brightening and allows dark areas to remain dark.
                sharpnessAmount: 0.85,
                localToneMapAmount: 0.3, // 0.5 -> 0.3: Greatly reduce the HDR feeling, retaining harsh light and shadow
                colorNoiseReductionAmount: 0.0, // 0.2 -> 0.0: Turn off noise reduction completely
                luminanceNoiseReductionAmount: 0.0,
                contrastAmount: 1.25,
                detailAmount: 0.9
            )
        case FilmPreset.fujiEterna.id: // F-Chrome: hard soft colors, low fidelity
            return RawDevelopmentConfig(
                boostAmount: 0.9,
                shadowBias: 0.0,
                sharpnessAmount: 0.5,
                localToneMapAmount: 0.6,
                colorNoiseReductionAmount: 0.3, // Preserve some color noise
                contrastAmount: 1.05
            )
        default: // common standards
            return RawDevelopmentConfig()
        }
    }

    /// Configure CIRAWFilter decoding parameters (core optimization method)
    /// - Parameters:
    ///   - rawFilter: filter object of raw data
    ///   - isNight: whether it is night scene mode
    ///   - deviceOrientation: device orientation when shooting (used to correct Raw orientation)
    ///   - cameraPosition: camera position (used to correct Raw direction)
    func configureRawFilter(
        _ rawFilter: CIRAWFilter,
        isNight: Bool = false,
        deviceOrientation: UIDeviceOrientation? = nil,
        cameraPosition: AVCaptureDevice.Position? = nil
    ) {
        let config = getCurrentRawConfig()
        let exif = rawFilter.properties[kCGImagePropertyExifDictionary as String] as? [String: Any]

        // 1. Orientation correction (for special cases such as iPhone 17 Pro)
        if let deviceOrientation, let cameraPosition {
            resolveRawOrientation(for: rawFilter, deviceOrientation: deviceOrientation, cameraPosition: cameraPosition)
        }

        // 2. Dynamic exposure benchmark
        // [FIX] Temporarily disable the FQSR algorithm as it causes the calculated EV to be too low in some scenarios.
        // [ADJUST] Globally improve RAW exposure base. RAW data is usually underexposed (exposed to the left) to protect highlights,
        // JPEGs will appear darker than straight out of camera. Here 0.8 EV is added to match regular visual brightness.
        let globalRawExposureOffset: Float = 0.8
        rawFilter.baselineExposure += globalRawExposureOffset

        if isNight {
            rawFilter.baselineExposure += 1.0 // Extra brightening of night scenes
        }

        // 3. Apply film style parameters
        rawFilter.boostAmount = config.boostAmount
        rawFilter.shadowBias = config.shadowBias

        if let contrast = config.contrastAmount, rawFilter.isContrastSupported {
            rawFilter.contrastAmount = contrast
        }
        if let detail = config.detailAmount, rawFilter.isDetailSupported {
            rawFilter.detailAmount = detail
        }

        // 4. Apply image quality enhancement parameters (ISP-level capabilities)
        if let sharp = rawFilter.inputKeys.contains(kCIInputSharpnessKey) ? config.sharpnessAmount : nil {
            rawFilter.setValue(sharp, forKey: kCIInputSharpnessKey)
        } else {
            // Fallback for older API or different key naming conventions if needed,
            // typically sharpnessAmount is a property on CIRAWFilter.
            rawFilter.sharpnessAmount = config.sharpnessAmount
        }

        if rawFilter.isLocalToneMapSupported {
            rawFilter.localToneMapAmount = config.localToneMapAmount
        }

        if rawFilter.isColorNoiseReductionSupported {
            rawFilter.colorNoiseReductionAmount = config.colorNoiseReductionAmount
        }

        if rawFilter.isLuminanceNoiseReductionSupported {
            rawFilter.luminanceNoiseReductionAmount = config.luminanceNoiseReductionAmount
        }

        if rawFilter.isMoireReductionSupported {
            rawFilter.moireReductionAmount = config.moireReductionAmount
        }

        // 5. Lens correction (enabled by default)
        if rawFilter.isLensCorrectionSupported {
            rawFilter.isLensCorrectionEnabled = true
        }
    }

    // MARK: - Helper Logic (Ported from tmp.swift)

    private func resolveRawOrientation(
        for rawFilter: CIRAWFilter,
        deviceOrientation: UIDeviceOrientation,
        cameraPosition: AVCaptureDevice.Position
    ) {
        // Only handles orientation correction for the front camera.
        // Rear cameras usually contain correct metadata, over-correction can result in wrong orientation or dimensions when shooting in landscape mode.
        guard cameraPosition == .front else { return }

        // For all models before iPhone 17, regardless of front or main camera, the output RAW orientation is .right
        // The RAW orientation of iPhone 17 Pro front output is .up
        if rawFilter.orientation == .right {
            rawFilter.orientation = resolveRawFilterOrientation(deviceOrientationOnCapture: deviceOrientation, isFront: cameraPosition == .front)
        } else if rawFilter.orientation == .up {
            rawFilter.orientation = resolveRawFilterOrientation4IPhone17ProFront(deviceOrientationOnCapture: deviceOrientation)
        }
    }

    private func resolveRawFilterOrientation(deviceOrientationOnCapture: UIDeviceOrientation, isFront: Bool) -> CGImagePropertyOrientation {
        switch deviceOrientationOnCapture {
        case .portrait:
            return .right
        case .landscapeLeft:
            return isFront ? .down : .up
        case .landscapeRight:
            return isFront ? .up : .down
        case .portraitUpsideDown:
            return .left
        default:
            return .up
        }
    }

    private func resolveRawFilterOrientation4IPhone17ProFront(deviceOrientationOnCapture: UIDeviceOrientation) -> CGImagePropertyOrientation {
        switch deviceOrientationOnCapture {
        case .portrait: return .up
        case .landscapeLeft: return .right
        case .landscapeRight: return .left
        case .portraitUpsideDown: return .down
        default: return .up
        }
    }

    private func interpolateValue(array1: [Float], array2: [Float], targetValue: Float) -> Float {
        if array1.count < 2 || array2.count < 2 { return targetValue }
        let start1 = array1[0]
        let end1 = array1[array1.count - 1]

        if targetValue < start1 || targetValue > end1 { return targetValue }

        let start2 = array2[0]
        let end2 = array2[array2.count - 1]

        let range1 = end1 - start1
        let range2 = end2 - start2

        if range1 == 0 { return start2 }

        let offset = targetValue - start1
        let factor = range2 / range1
        return start2 + (offset * factor)
    }
}
