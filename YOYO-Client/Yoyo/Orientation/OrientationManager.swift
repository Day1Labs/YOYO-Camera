import AVFoundation
import Combine
import CoreMotion
import Foundation
import UIKit

final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    @Published var currentDeviceOrientation: UIDeviceOrientation = .portrait {
        didSet {
            if oldValue != currentDeviceOrientation, currentDeviceOrientation.isValidInterfaceOrientation {
                onOrientationChanged?(currentDeviceOrientation)
            }
        }
    }

    var currentAVCaptureVideoOrientation: AVCaptureVideoOrientation {
        .portrait
    }

    var onOrientationChanged: ((UIDeviceOrientation) -> Void)?

    private var isMonitoring = false

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.2
            motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
                guard let self else { return }
                if error != nil {
                    DispatchQueue.main.async {
                        self.motionManager.stopAccelerometerUpdates()
                        self.setupFallbackOrientationMonitoring()
                    }
                    return
                }
                guard let accelerometerData = data else { return }
                let newOrientation = self.orientationFrom(acceleration: accelerometerData.acceleration)
                if newOrientation != self.currentDeviceOrientation {
                    DispatchQueue.main.async {
                        self.currentDeviceOrientation = newOrientation
                    }
                }
            }
        } else {
            setupFallbackOrientationMonitoring()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func setupFallbackOrientationMonitoring() {
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    @objc private func deviceOrientationDidChange() {
        let newOrientation = UIDevice.current.orientation
        guard newOrientation.isValidInterfaceOrientation else { return }
        if newOrientation != currentDeviceOrientation {
            currentDeviceOrientation = newOrientation
        }
    }

    private func orientationFrom(acceleration: CMAcceleration) -> UIDeviceOrientation {
        let threshold = 0.6
        let x = acceleration.x
        let y = acceleration.y
        let z = acceleration.z

        // If the device is lying flat (Z-axis component is large), maintain the current orientation
        if abs(z) > 0.85 {
            return currentDeviceOrientation
        }

        // Compare the absolute values ​​of X and Y, giving priority to the axis with a larger tilt angle
        if abs(x) > abs(y) {
            if x >= threshold {
                return .landscapeRight
            } else if x <= -threshold {
                return .landscapeLeft
            }
        } else {
            if y <= -threshold {
                return .portrait
            } else if y >= threshold {
                return .portraitUpsideDown
            }
        }
        return currentDeviceOrientation
    }

    /// Calculated property of button rotation angle on interface
    static func rotationAngle(_ deviceOrientation: UIDeviceOrientation) -> Double {
        switch deviceOrientation {
        case .landscapeLeft:
            return 90
        case .landscapeRight:
            return -90
        case .portraitUpsideDown:
            return 180
        default:
            return 0
        }
    }

    /// Map device orientation to EXIF ​​orientation for CIImage rotation
    /// Note: Since the VideoConnectionManager already handles mirroring of the front camera at the connection layer (isVideoMirrored = true),
    /// There is no need to re-apply the mirror here, just the rotation.
    static func exifOrientation(from deviceOrientation: UIDeviceOrientation, isFrontCamera _: Bool = false) -> Int32 {
        switch deviceOrientation {
        case .portrait:
            return 1 // Up
        case .landscapeLeft:
            return 8 // Rotate 90 CCW
        case .landscapeRight:
            return 6 // Rotate 90 CW
        case .portraitUpsideDown:
            return 3 // Rotate 180
        default:
            return 1
        }
    }
}
