import AVFoundation
import CoreImage
import SwiftUI

// MARK: - Suggested camera parameters

struct CameraSettings {
    let zoom: Double?
    let focusPoint: CGPoint?
    let exposureBias: Float?
    let iso: Int?
    let shutterSpeed: CMTime?
    let filter: FilterIdentifier?
    let flashMode: AVCaptureDevice.FlashMode?
    let whiteBalance: (temperature: Float, tint: Float)? // Color temperature and tint (can be nil, meaning AWB is used)
}
