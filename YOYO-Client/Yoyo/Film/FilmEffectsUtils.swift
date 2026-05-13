import CoreImage
import CoreImage.CIFilterBuiltins

enum FilmEffectUtils {
    static func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
        min(max(value, minValue), maxValue)
    }

    static func gaussianBlur(_ image: CIImage, radius: Float) -> CIImage {
        if radius <= 0.001 { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = radius
        return blur.outputImage ?? image
    }

    static func scaleImageKeepingOrigin(_ image: CIImage, scale: CGFloat) -> CIImage {
        let extent = image.extent
        if abs(scale - 1.0) < 0.0001 { return image }

        var translated = image.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
        let scaler = CIFilter.lanczosScaleTransform()
        scaler.inputImage = translated
        scaler.scale = Float(scale)
        scaler.aspectRatio = 1.0
        translated = scaler.outputImage ?? translated
        return translated.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }

    /// Progressive upsampling avoids block artifacts at large magnifications.
    static func progressiveUpsample(_ image: CIImage, targetExtent: CGRect) -> CIImage {
        let sourceExtent = image.extent
        let scale = max(targetExtent.width / sourceExtent.width, targetExtent.height / sourceExtent.height)

        if scale <= 2.0 {
            return scaleImageKeepingOrigin(image, scale: scale).cropped(to: targetExtent)
        }

        var currentImage = image
        var currentScale: CGFloat = 1.0

        while currentScale * 2.0 <= scale {
            currentImage = scaleImageKeepingOrigin(currentImage, scale: 2.0)
            currentScale *= 2.0
        }

        if currentScale < scale {
            currentImage = scaleImageKeepingOrigin(currentImage, scale: scale / currentScale)
        }

        return currentImage.cropped(to: targetExtent)
    }

    static func addImages(_ background: CIImage, _ foreground: CIImage) -> CIImage {
        let add = CIFilter.additionCompositing()
        add.inputImage = foreground
        add.backgroundImage = background
        return add.outputImage ?? background
    }

    static func screenBlendImages(_ background: CIImage, _ foreground: CIImage) -> CIImage {
        let blend = CIFilter.screenBlendMode()
        blend.inputImage = foreground
        blend.backgroundImage = background
        return blend.outputImage ?? background
    }

    /// Load `CIColorKernel` from the Metal library.
    static func loadColorKernel(name: String) -> CIColorKernel? {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? CIColorKernel(functionName: name, fromMetalLibraryData: data)
    }

    /// Load a generic `CIKernel` from the Metal library.
    static func loadGeneralKernel(name: String) -> CIKernel? {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? CIKernel(functionName: name, fromMetalLibraryData: data)
    }
}
