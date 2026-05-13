import CoreImage
import Foundation

/// A unified image adjustment processor that provides rendering logic shared by layers and the entire image.
enum ImageAdjuster {
    /// Basic adjustment parameter structure
    struct Adjustments {
        var exposure: Float = 0.0
        var contrast: Float = 0.0
        var saturation: Float = 1.0
        var brightness: Float = 0.0
        var hue: Float = 0.0
        var temperature: Float = 0.0
        var tint: Float = 0.0
        var highlights: Float = 0.0
        var shadows: Float = 0.0
        var whites: Float = 0.0
        var blacks: Float = 0.0
        var vibrance: Float = 0.0
        var texture: Float = 0.0
        var clarity: Float = 0.0
        var dehaze: Float = 0.0
        var sharpening: Float = 0.0

        static let `default` = Adjustments()
    }

    /// Apply standard image adjustment chain
    static func applyAdjustments(_ adjustments: Adjustments, to image: CIImage) -> CIImage {
        var result = image

        // 1. Exposure
        if abs(adjustments.exposure) > 0.001 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: adjustments.exposure,
            ])
        }

        // 2. Highlights & Shadows
        if abs(adjustments.highlights) > 0.001 || abs(adjustments.shadows) > 0.001 {
            let hl = adjustments.highlights
            let sh = adjustments.shadows

            let targetHighlight: Float
            if hl < 0 {
                targetHighlight = 1.0 + hl * 0.7
            } else {
                targetHighlight = 1.0 + hl * 0.2
            }

            let targetShadow: Float
            if sh < 0 {
                targetShadow = sh * 0.4
            } else {
                targetShadow = sh
            }

            result = result.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": targetHighlight,
                "inputShadowAmount": targetShadow,
            ])
        }

        // 3. Whites & Blacks
        if abs(adjustments.whites) > 0.001 || abs(adjustments.blacks) > 0.001 {
            let whites = adjustments.whites
            let blacks = adjustments.blacks

            let whitePoint = 1.0 - whites * 0.25
            let blackPoint = -blacks * 0.15

            let slope = 1.0 / max(0.01, whitePoint - blackPoint)
            let bias = -blackPoint * slope

            result = result.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(slope), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(slope), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(slope), w: 0),
                "inputBiasVector": CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 0),
            ])
        }

        // 4. Contrast
        if abs(adjustments.contrast) > 0.001 {
            // Note: 0 is the standard in layer mode, and 0.5 is the standard in FilmEmulation.
            // The offset is used uniformly here, 0 means no change
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.0 + adjustments.contrast,
            ])
        }

        // 5. Saturation
        if abs(adjustments.saturation - 1.0) > 0.001 {
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: adjustments.saturation,
            ])
        }

        // 6. Vibrance
        if abs(adjustments.vibrance) > 0.001 {
            result = result.applyingFilter("CIVibrance", parameters: [
                "inputAmount": adjustments.vibrance,
            ])
        }

        // 7. Brightness
        if abs(adjustments.brightness) > 0.001 {
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: adjustments.brightness,
            ])
        }

        // 8. Hue
        if abs(adjustments.hue) > 0.001 {
            result = result.applyingFilter("CIHueAdjust", parameters: [
                kCIInputAngleKey: adjustments.hue * .pi,
            ])
        }

        // 9. Temperature & Tint
        if abs(adjustments.temperature) > 0.001 || abs(adjustments.tint) > 0.001 {
            // Using the logic of LayerManager, the logic of FilmEmulation is slightly different but the goal is the same
            // Uniformly use the implementation of LayerManager, which is more direct
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500 + CGFloat(adjustments.temperature) * 2000, y: 0),
                "inputTargetNeutral": CIVector(x: 6500, y: CGFloat(adjustments.tint) * 200),
            ])
        }

        // 10. Texture
        if abs(adjustments.texture) > 0.001 {
            let intensity = adjustments.texture * 1.5
            if intensity > 0 {
                result = result.applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: 0.8,
                    kCIInputIntensityKey: intensity,
                ])
            } else {
                result = result.applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: abs(intensity) * 1.5,
                ]).cropped(to: result.extent)
            }
        }

        // 11. Clarity
        if abs(adjustments.clarity) > 0.001 {
            let intensity = adjustments.clarity * 0.8
            if intensity > 0 {
                result = result.applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: 20.0,
                    kCIInputIntensityKey: intensity,
                ])
            } else {
                let blur = result.applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: abs(intensity) * 10.0,
                ]).cropped(to: result.extent)
                result = blur.applyingFilter("CIOverlayBlendMode", parameters: [
                    "inputBackgroundImage": result,
                ])
            }
        }

        // 12. Dehaze
        if abs(adjustments.dehaze) > 0.001 {
            let contrastValue = 1.0 + adjustments.dehaze * 0.2
            let saturationValue = 1.0 + adjustments.dehaze * 0.1
            let exposureValue = -adjustments.dehaze * 0.1

            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: contrastValue,
                kCIInputSaturationKey: saturationValue,
                kCIInputBrightnessKey: exposureValue,
            ])
        }

        // 13. Sharpening
        if abs(adjustments.sharpening) > 0.001 {
            result = result.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: adjustments.sharpening * 2.0,
            ])
        }

        return result
    }
}
