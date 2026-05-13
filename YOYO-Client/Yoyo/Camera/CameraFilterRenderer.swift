import CoreImage
import Metal
import UIKit

final class CameraFilterRenderer {
    static let shared = CameraFilterRenderer()

    private let metalDevice: MTLDevice?
    private let ciContext: CIContext
    private var commandQueue: MTLCommandQueue?
    /// Use the Display P3 wide color gamut for preview rendering to fully leverage iPhone display colors
    private let renderColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    private let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()

    // Cached properties
    private var lastDrawableSize: CGSize = .zero
    private var lastImageExtent: CGRect = .zero
    private var cachedTransform: CGAffineTransform?

    private init() {
        metalDevice = MTLCreateSystemDefaultDevice()
        if let device = metalDevice {
            ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: workingColorSpace,
                .outputColorSpace: renderColorSpace,
                .cacheIntermediates: true, // Avoid temporary volatile textures
            ])
            commandQueue = device.makeCommandQueue()
            commandQueue?.label = "com.day1-labs.yoyo.camera.filter.render"
        } else {
            ciContext = CIContext(options: [
                .workingColorSpace: workingColorSpace,
                .outputColorSpace: renderColorSpace,
                .cacheIntermediates: true,
            ])
        }
    }

    @discardableResult
    func renderPreview(to metalLayer: CAMetalLayer, with sourceImage: CIImage) -> MTLCommandBuffer? {
        autoreleasepool {
            guard let commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let drawable = metalLayer.nextDrawable()
            else {
                return nil
            }

            let filteredImage = applyFilter(to: sourceImage)
            let destinationTexture = drawable.texture
            let imageExtent = filteredImage.extent
            let drawableSize = metalLayer.drawableSize

            // Check the cache
            let transform: CGAffineTransform
            if drawableSize == lastDrawableSize, imageExtent == lastImageExtent, let cached = cachedTransform {
                transform = cached
            } else {
                // Recompute
                let scaleX = drawableSize.width / imageExtent.width
                let scaleY = drawableSize.height / imageExtent.height
                let scale = max(scaleX, scaleY)
                let tx = (drawableSize.width - imageExtent.width * scale) / 2 - imageExtent.origin.x * scale
                let ty = (drawableSize.height - imageExtent.height * scale) / 2 - imageExtent.origin.y * scale

                transform = CGAffineTransform(scaleX: scale, y: scale)
                    .concatenating(CGAffineTransform(translationX: tx, y: ty))

                // Update the cache
                lastDrawableSize = drawableSize
                lastImageExtent = imageExtent
                cachedTransform = transform
            }

            let finalImageToRender = filteredImage.transformed(by: transform)

            ciContext.render(
                finalImageToRender,
                to: destinationTexture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawableSize),
                colorSpace: renderColorSpace
            )

            commandBuffer.present(drawable)
            return commandBuffer
        }
    }

    func applyFilter(to image: CIImage) -> CIImage {
        FilterManager.shared.applyFilter(to: image, quality: .preview)
    }
}
