import AVFoundation
import Combine
import CoreImage
import UIKit

/// previewcontroller, and UIImage
@MainActor
final class PreviewFrameProvider: ObservableObject {
    static let shared = PreviewFrameProvider(renderController: .shared)

    private let renderController: PreviewRenderController
    private let ciContext = CIContext(options: nil)
    private var latestSampleBuffer: CMSampleBuffer?

    private init(renderController: PreviewRenderController) {
        self.renderController = renderController
        subscribeToFrames()
    }

    /// get UIImage, orientationcurrentdeviceorientation()
    func latestImage() -> UIImage? {
        guard let buffer = latestSampleBuffer,
              let imageBuffer = CMSampleBufferGetImageBuffer(buffer)
        else {
            return nil
        }

        var ciImage = CIImage(cvPixelBuffer: imageBuffer)

        // 1. getmirroring
        let deviceOrientation = OrientationManager.shared.currentDeviceOrientation
        let isFrontCamera = CameraDeviceManager.shared.currentCamera?.position == .front
        let exifOrientation = OrientationManager.exifOrientation(from: deviceOrientation, isFrontCamera: isFrontCamera)

        // 2. physical, (Bake orientation into pixels)
        ciImage = ciImage.oriented(forExifOrientation: exifOrientation)

        // 3. preview (image)
        var targetRatio = CameraSettingsState.shared.effectiveAspectRatio

        // ifdevicelandscape, portrait App previewphysical,,
        // , so
        if deviceOrientation.isLandscape {
            targetRatio = 1.0 / targetRatio
        }

        let extent = ciImage.extent
        let currentRatio = extent.width / extent.height

        var cropRect = extent
        if abs(targetRatio - currentRatio) > 0.01 {
            if targetRatio > currentRatio {
                // currentimage"",
                let newHeight = extent.width / CGFloat(targetRatio)
                let yOffset = (extent.height - newHeight) / 2
                cropRect = CGRect(x: extent.origin.x, y: extent.origin.y + yOffset, width: extent.width, height: newHeight)
            } else {
                // currentimage"",
                let newWidth = extent.height * CGFloat(targetRatio)
                let xOffset = (extent.width - newWidth) / 2
                cropRect = CGRect(x: extent.origin.x + xOffset, y: extent.origin.y, width: newWidth, height: extent.height)
            }
            ciImage = ciImage.cropped(to: cropRect)
        }

        // 4. CGImage and(orientation.up)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    private func subscribeToFrames() {
        renderController.frameSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sampleBuffer in
                self?.latestSampleBuffer = sampleBuffer
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}
