import AVFoundation
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

/// Auxiliary image helpers copied from `CameraPreviewView`.
extension UIImage {
    /// Generate HEIC data.
    /// Note: This is currently retained for future optimization.
    func heicData(compressionQuality: CGFloat = 0.75) -> Data? {
        guard #available(iOS 11.0, *), let cgImage else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    func cropped(to aspectRatio: Double, orientation: UIDeviceOrientation = .portrait) -> UIImage? {
        guard let cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let isLandscape = orientation.isLandscape
        var finalAspectRatio = aspectRatio
        if isLandscape, aspectRatio != 1.0 { // Do not swap for square (1:1)
            finalAspectRatio = 1.0 / aspectRatio
        }
        let orientedSize = ciImage.extent.size
        let targetAspectRatio = finalAspectRatio
        let imageAspectRatio = orientedSize.width / orientedSize.height
        var cropRect = ciImage.extent
        if imageAspectRatio > targetAspectRatio {
            let newWidth = orientedSize.height * targetAspectRatio
            let xOrigin = (orientedSize.width - newWidth) / 2
            cropRect = CGRect(x: xOrigin, y: 0, width: newWidth, height: orientedSize.height)
        } else {
            let newHeight = orientedSize.width / targetAspectRatio
            let yOrigin = (orientedSize.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: yOrigin, width: orientedSize.width, height: newHeight)
        }
        let croppedImage = ciImage.cropped(to: cropRect)
        let context = CIContext()
        if let cgCropped = context.createCGImage(croppedImage, from: croppedImage.extent) {
            return UIImage(cgImage: cgCropped, scale: scale, orientation: imageOrientation)
        }
        return nil
    }
}
