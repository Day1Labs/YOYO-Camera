import AVFoundation
import CoreImage
import CoreMotion
import UIKit

/// imageresult
struct ProcessedImageResult {
    let originalImage: UIImage
    let filteredImage: UIImage
}

/// image - imagefeatures
final class ImageProcessor {
    static let shared = ImageProcessor(orientationManager: .shared)

    // MARK: - Properties

    private let ciContext: CIContext
    private weak var orientationManager: OrientationManager?

    /// cache ColorSpace (C)
    /// use Display P3, iPhone capability
    private let colorSpace: CGColorSpace

    // MARK: - Initialization

    private init(orientationManager: OrientationManager?) {
        self.orientationManager = orientationManager

        // initialization ColorSpace - use Display P3
        colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

        let workingSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false,
            .outputColorSpace: colorSpace,
            .workingColorSpace: workingSpace,
            .cacheIntermediates: false,
        ])
    }

    deinit {
        ciContext.clearCaches()
    }

    // MARK: - Public Methods

    /// image: filter,, orientation
    /// completeclean up CIContext cache
    func processImage(
        _ ciImage: CIImage,
        aspectRatio: Double,
        applyFilter: Bool = true,
        fixedOrientation: UIImage.Orientation? = nil
    ) -> ProcessedImageResult? {
        // 1.
        guard let croppedImage = cropImage(ciImage, to: aspectRatio) else {
            return nil
        }

        // 2. filter
        let filteredImage: CIImage
        if applyFilter {
            // Raw PhotoProcessor CIRAWFilter complete, here CIImage
            filteredImage = FilterManager.shared.applyFilter(to: croppedImage, quality: .full)
        } else {
            filteredImage = croppedImage
        }

        // 3. UIImage
        let uiImageOrientation = fixedOrientation ?? getUIImageOrientation()

        guard let originalCGImage = renderCGImage(from: croppedImage, colorSpace: colorSpace),
              let filteredCGImage = renderCGImage(from: filteredImage, colorSpace: colorSpace)
        else {
            return nil
        }

        let originalUIImage = UIImage(cgImage: originalCGImage, scale: 1, orientation: uiImageOrientation)
        let filteredUIImage = UIImage(cgImage: filteredCGImage, scale: 1, orientation: uiImageOrientation)

        // D: completeclean up CIContext cache, releasemiddleresultmemory
        ciContext.clearCaches()

        return ProcessedImageResult(
            originalImage: originalUIImage,
            filteredImage: filteredUIImage
        )
    }

    /// filterCIImage
    func applyImageFilter(to image: CIImage) -> CIImage {
        FilterManager.shared.applyFilter(to: image, quality: .full)
    }

    /// image
    func cropImage(_ ciImage: CIImage, to aspectRatio: Double) -> CIImage? {
        let extent = ciImage.extent
        guard extent.isFinite, !extent.isEmpty else { return nil }

        let size = extent.size
        let imageAspectRatio = size.width / size.height
        var cropRect = extent

        if imageAspectRatio > aspectRatio {
            let newWidth = size.height * aspectRatio
            let xOrigin = extent.origin.x + (size.width - newWidth) / 2
            cropRect = CGRect(x: xOrigin, y: extent.origin.y, width: newWidth, height: size.height)
        } else {
            let newHeight = size.width / aspectRatio
            let yOrigin = extent.origin.y + (size.height - newHeight) / 2
            cropRect = CGRect(x: extent.origin.x, y: yOrigin, width: size.width, height: newHeight)
        }

        guard cropRect.isFinite, !cropRect.isEmpty else { return nil }

        let boundedCropRect = cropRect.intersection(extent)
        guard !boundedCropRect.isEmpty else { return nil }

        // ensure
        var integralRect = boundedCropRect.integral
        var width = floor(integralRect.width)
        var height = floor(integralRect.height)
        if width.truncatingRemainder(dividingBy: 2) != 0 { width -= 1 }
        if height.truncatingRemainder(dividingBy: 2) != 0 { height -= 1 }
        integralRect.size = CGSize(width: max(width, 2), height: max(height, 2))

        return ciImage.cropped(to: integralRect)
    }

    /// CIImageCGImage
    func renderCGImage(from ciImage: CIImage, colorSpace: CGColorSpace) -> CGImage? {
        let extent = ciImage.extent
        guard extent.isFinite && !extent.isEmpty else { return nil }

        let maxDimension: CGFloat = 8192
        var imageToRender = ciImage.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
        var renderExtent = CGRect(origin: .zero, size: extent.size)

        if extent.width > maxDimension || extent.height > maxDimension {
            let scale = min(maxDimension / extent.width, maxDimension / extent.height)
            imageToRender = imageToRender.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let scaledWidth = floor(extent.width * scale)
            let scaledHeight = floor(extent.height * scale)
            let evenWidth = scaledWidth.truncatingRemainder(dividingBy: 2) == 0 ? scaledWidth : scaledWidth - 1
            let evenHeight = scaledHeight.truncatingRemainder(dividingBy: 2) == 0 ? scaledHeight : scaledHeight - 1
            renderExtent = CGRect(x: 0, y: 0, width: evenWidth, height: evenHeight)
        } else {
            let w = floor(extent.width)
            let h = floor(extent.height)
            let ew = w.truncatingRemainder(dividingBy: 2) == 0 ? w : w - 1
            let eh = h.truncatingRemainder(dividingBy: 2) == 0 ? h : h - 1
            renderExtent = CGRect(x: 0, y: 0, width: ew, height: eh)
        }

        // Alpha CGImage, thenno Alpha RGB context, Photos AlphaPremulLast
        guard let cgImageWithAlpha = ciContext.createCGImage(imageToRender, from: renderExtent, format: .BGRA8, colorSpace: colorSpace) else {
            return nil
        }

        let width = Int(renderExtent.width)
        let height = Int(renderExtent.height)
        let bitsPerComponent = 8
        let bytesPerRow = 0 // let CoreGraphics

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.draw(cgImageWithAlpha, in: CGRect(origin: .zero, size: CGSize(width: renderExtent.width, height: renderExtent.height)))
        return context.makeImage()
    }

    /// clean upcache
    func clearCaches() {
        ciContext.clearCaches()
    }

    // MARK: - Private Methods

    private func getUIImageOrientation() -> UIImage.Orientation {
        guard let orientationManager else { return .up }

        switch orientationManager.currentDeviceOrientation {
        case .portrait:
            return .up
        case .portraitUpsideDown:
            return .down
        case .landscapeLeft:
            return .left
        case .landscapeRight:
            return .right
        default:
            return .up
        }
    }
}
