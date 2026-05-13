import AVFoundation
import UIKit

/// Zoom gesture handler - encapsulates all state management and logic related to zoom gestures
/// ,, features
final class ZoomGestureHandler {
    // MARK: - Properties

    /// initial zoom level when the gesture begins
    private var initialZoomLevel: Double = 1.0

    /// time of the last gesture update
    private var lastGestureUpdateTime: Date = .init()

    /// zoom(used for)
    private var lastProcessedZoomLevel: Double = 1.0

    /// zoom points where haptic feedback has already been triggered
    private var zoomLevelCrossedThresholds: Set<Double> = []

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// handle zooming for pinch gestures
    /// - Parameters:
    ///   - scale: gesture scale value
    ///   - state: gesture state
    func handlePinchGesture(scale: CGFloat, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            handleGestureBegan()

        case .changed:
            handleGestureChanged(scale: scale)

        case .ended, .cancelled:
            handleGestureEnded()

        default:
            break
        }
    }

    // MARK: - Private Methods - Gesture State Handling

    /// handle gesture begin
    private func handleGestureBegan() {
        // zoomstate
        initialZoomLevel = ZoomManager.shared.deviceZoomFactor
        lastProcessedZoomLevel = initialZoomLevel
        lastGestureUpdateTime = Date()
        zoomLevelCrossedThresholds.removeAll()

        print("[Zoom Gesture] 🎬 Pinch began - Initial: \(String(format: "%.2f", initialZoomLevel))x")
    }

    /// handle gesture changes
    private func handleGestureChanged(scale: CGFloat) {
        // gesturezoom(gesturedeviceswitch)
        ZoomManager.shared.applyGestureZoom(Double(scale), baseZoom: initialZoomLevel)

        // updatezoom
        lastProcessedZoomLevel = ZoomManager.shared.deviceZoomFactor

        // print("[Zoom Gesture] 📊 Scale: \(String(format: "%.3f", scale)), Current: \(String(format: "%.2f", currentZoom))x")
    }

    /// handle gesture end
    private func handleGestureEnded() {
        let finalZoom = ZoomManager.shared.deviceZoomFactor
        print("[Zoom Gesture] ✅ Pinch ended - Final: \(String(format: "%.2f", finalZoom))x")

        // gestureend, checkwhetherneed to switchdevice
        // use allowDeviceSwitch: true let ZoomManager
        ZoomManager.shared.setZoomFactor(finalZoom)

        // clean upstate
        zoomLevelCrossedThresholds.removeAll()
    }
}
