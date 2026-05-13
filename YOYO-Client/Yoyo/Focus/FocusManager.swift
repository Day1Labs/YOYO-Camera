import AVFoundation
import Combine
import SwiftUI

// MARK: - Focus status enum

enum FocusState {
    case idle
    case focusing
    case locked
    case failed
}

// MARK: - focus mode enum

enum FocusMode {
    case center // center focus
    case tap // Click to focus
    case continuous // continuous focus
    case locked // lock focus
}

// MARK: - Focus Manager

final class FocusManager: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = FocusManager()

    // MARK: - Published Properties

    @Published private(set) var focusState: FocusState = .idle
    @Published var focusMode: FocusMode = .center
    @Published private(set) var focusPoint: CGPoint = .init(x: 0.5, y: 0.5)
    @Published private(set) var isShowingFocusIndicator: Bool = false
    @Published private(set) var isFocusLocked: Bool = false
    @Published var manualFocusPosition: Float = 0.0 {
        didSet {
            if oldValue != manualFocusPosition, isManualFocusMode {
                adjustFocusPosition(manualFocusPosition)
            }
        }
    }

    @Published private(set) var canAdjustFocus: Bool = false
    @Published private(set) var isManualFocusMode: Bool = false
    @Published private(set) var currentLensPosition: Float = 0.0

    var previewSize: CGSize = .zero
    var previewOrigin: CGPoint = .zero

    private var currentCamera: AVCaptureDevice?
    private var focusIndicatorTimer: Timer?
    private var longPressTimer: Timer?

    private var focusStateChangeCallback: ((FocusState) -> Void)?

    override private init() {
        super.init()
    }

    func setPreviewState(state: FocusState = .idle, isLocked: Bool = false) {
        DispatchQueue.main.async {
            self.focusState = state
            self.isFocusLocked = isLocked
        }
    }

    func setCurrentCamera(_ camera: AVCaptureDevice?) {
        // ✅ Avoid repeated initialization: if the camera has not changed, return directly
        if let current = currentCamera, let new = camera, current === new {
            print("[Focus Debug] ⏭️ Camera unchanged, skipping re-initialization")
            return
        }

        removeCurrentCameraObservers()
        currentCamera = camera
        setupCameraObservers()

        updateFocusCapability()

        // ✅ Critical fix: Automatically reinitialize focus mode after device switching
        // Ensure your new camera immediately enables optimal focus mode to avoid out-of-focus issues
        if let camera {
            print("[Focus Debug] 📍 Auto-initializing focus for new camera: \(camera.deviceType.rawValue)")

            // Choose the best focus mode and apply it instantly
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                print("[Focus Debug] ✅ Enabling continuous autofocus")
                enableContinuousAutoFocus()
            } else if camera.isFocusModeSupported(.autoFocus) {
                print("[Focus Debug] ✅ Enabling center focus (fallback)")
                focusAtCenter()
            } else {
                print("[Focus Debug] ⚠️ No autofocus modes supported")
            }
        } else {
            print("[Focus Debug] ⚠️ Camera is nil, skipping focus initialization")
        }
    }

    func setPreviewSize(_ size: CGSize) {
        previewSize = size
    }

    func setPreviewFrame(_ frame: CGRect) {
        previewOrigin = frame.origin
        previewSize = frame.size
    }

    func setFocusStateChangeCallback(_ callback: @escaping (FocusState) -> Void) {
        focusStateChangeCallback = callback
    }

    func startLongPress(at point: CGPoint) {
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            DispatchQueue.main.async {
                self.lockFocus(at: point)
            }
        }
    }

    func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    /// lock focus
    func lockFocus(at point: CGPoint) {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            let devicePoint = convertPointToDeviceCoordinates(point)

            // Set focus point
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = devicePoint
            }

            // lock focus
            if camera.isFocusModeSupported(.locked) {
                camera.focusMode = .locked
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.focusPoint = point
                self.isFocusLocked = true
                self.focusMode = .locked
                self.focusState = .locked
                self.showFocusIndicator()
            }

        } catch {
            print("Focus Lock error: \(error)")
        }
    }

    /// Unlock focus
    func unlockFocus() {
        guard let camera = currentCamera, isFocusLocked else { return }

        do {
            try camera.lockForConfiguration()

            // Restore autofocus
            if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.isFocusLocked = false
                self.focusMode = .center
                self.focusState = .idle
                self.isShowingFocusIndicator = false
            }

        } catch {
            print("Focus Unlock error: \(error)")
        }
    }

    func focusAtDevicePoint(_ devicePoint: CGPoint) {
        guard let camera = currentCamera,
              camera.isFocusPointOfInterestSupported
        else {
            return
        }

        DispatchQueue.main.async {
            let viewPoint = CGPoint(x: devicePoint.x * self.previewSize.width + self.previewOrigin.x,
                                    y: devicePoint.y * self.previewSize.height + self.previewOrigin.y)
            self.focusPoint = viewPoint
            self.focusState = .focusing
            self.showFocusIndicator()
        }

        do {
            try camera.lockForConfiguration()
            camera.focusPointOfInterest = devicePoint
            if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }
            camera.unlockForConfiguration()
        } catch {
            print("Focus error: \(error)")
            DispatchQueue.main.async {
                self.focusState = .failed
            }
        }
    }

    func focusAtCenter() {
        guard let camera = currentCamera else { return }

        let centerPoint = CGPoint(x: 0.5, y: 0.5)

        do {
            try camera.lockForConfiguration()
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = centerPoint
            }
            if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }
            camera.unlockForConfiguration()
            let viewCenterPoint = CGPoint(x: previewOrigin.x + previewSize.width / 2,
                                          y: previewOrigin.y + previewSize.height / 2)
            DispatchQueue.main.async {
                self.focusPoint = viewCenterPoint
                self.showFocusIndicator()
                self.focusState = .focusing
            }

        } catch {
            print("Center focus error: \(error)")
            DispatchQueue.main.async {
                self.focusState = .failed
            }
        }
    }

    /// Click to focus
    func focus(at point: CGPoint) {
        guard let camera = currentCamera,
              camera.isFocusPointOfInterestSupported
        else {
            return
        }

        // Switch to tap mode on click
        if focusMode != .tap {
            focusMode = .tap
        }

        // Update UI status immediately to give users instant feedback
        DispatchQueue.main.async {
            self.focusPoint = point
            self.focusState = .focusing
            self.showFocusIndicator()
        }

        // Transform the coordinate system (from view coordinates to camera coordinates)
        let devicePoint = convertPointToDeviceCoordinates(point)

        do {
            try camera.lockForConfiguration()

            // Set focus point
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = devicePoint
            }

            // Set focus mode
            if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            camera.unlockForConfiguration()

        } catch {
            print("Focus error: \(error)")
            DispatchQueue.main.async {
                self.focusState = .failed
            }
        }
    }

    func resetFocusToCenter() {
        let centerPoint = CGPoint(x: previewOrigin.x + previewSize.width / 2,
                                  y: previewOrigin.y + previewSize.height / 2)
        focus(at: centerPoint)
    }

    /// Set continuous autofocus
    func enableContinuousAutoFocus() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // Set continuous autofocus
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.focusMode = .continuous
                self.focusState = .idle
            }

        } catch {
            print("Continuous focus setup error: \(error)")
        }
    }

    /// Disable continuous autofocus
    func disableContinuousAutoFocus() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // Switch to autofocus mode
            if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.focusMode = .center
            }

        } catch {
            print("Disable continuous focus error: \(error)")
        }
    }

    /// Check whether the current device supports focus
    func isFocusSupported() -> Bool {
        guard let camera = currentCamera else { return false }
        return camera.isFocusPointOfInterestSupported ||
            camera.isFocusModeSupported(.autoFocus) ||
            camera.isFocusModeSupported(.continuousAutoFocus)
    }

    /// Get the focus mode supported by the current device
    func getSupportedFocusModes() -> [FocusMode] {
        guard let camera = currentCamera else { return [] }

        var supportedModes: [FocusMode] = []

        if camera.isFocusModeSupported(.autoFocus) {
            supportedModes.append(.center)
        }

        if camera.isFocusPointOfInterestSupported {
            supportedModes.append(.tap)
        }

        if camera.isFocusModeSupported(.continuousAutoFocus) {
            supportedModes.append(.continuous)
        }

        if camera.isFocusModeSupported(.locked) {
            supportedModes.append(.locked)
        }

        return supportedModes
    }

    /// Get user-friendly mode icons
    var modeIcon: String {
        if isFocusLocked {
            return "camera.viewfinder"
        }

        switch focusMode {
        case .tap:
            return "hand.tap"
        default:
            return "camera.viewfinder"
        }
    }

    /// Check if focus button should be shown
    var shouldShowFocusButton: Bool {
        let supportedModes = getSupportedFocusModes()
        return supportedModes.count > 1 || isFocusLocked
    }

    // MARK: - Private Methods

    /// Set camera observer
    private func setupCameraObservers() {
        guard let camera = currentCamera else { return }

        // Monitor focus status changes
        camera.addObserver(self, forKeyPath: "adjustingFocus", options: [.new], context: nil)
        camera.addObserver(self, forKeyPath: "lensPosition", options: [.new], context: nil)
    }

    /// Remove current camera observer
    private func removeCurrentCameraObservers() {
        guard let camera = currentCamera else { return }

        camera.removeObserver(self, forKeyPath: "adjustingFocus", context: nil)
        camera.removeObserver(self, forKeyPath: "lensPosition", context: nil)
    }

    private func convertPointToDeviceCoordinates(_ point: CGPoint) -> CGPoint {
        guard previewSize.width > 0, previewSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let localX = (point.x - previewOrigin.x) / previewSize.width
        let localY = (point.y - previewOrigin.y) / previewSize.height
        let x = max(0, min(1, localX))
        let y = max(0, min(1, localY))
        return CGPoint(x: x, y: y)
    }

    /// Show focus indicator
    private func showFocusIndicator() {
        isShowingFocusIndicator = true

        // Cancel previous timer
        focusIndicatorTimer?.invalidate()

        // Set a new timer to hide the indicator after 2 seconds (unless in locked mode)
        if focusMode != .locked {
            focusIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.isShowingFocusIndicator = false
                }
            }
        }
    }

    private func updateFocusCapability() {
        guard let camera = currentCamera else {
            DispatchQueue.main.async {
                self.canAdjustFocus = false
                self.isManualFocusMode = false
                self.currentLensPosition = 0.0
                self.manualFocusPosition = 0.0
            }
            return
        }
        let supported = camera.isLockingFocusWithCustomLensPositionSupported
        let lens = camera.lensPosition
        DispatchQueue.main.async {
            self.canAdjustFocus = supported
            self.currentLensPosition = lens
            self.manualFocusPosition = lens
            if !supported { self.isManualFocusMode = false }
        }
    }

    func enableManualFocus() {
        guard let camera = currentCamera, canAdjustFocus else { return }
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.locked) {
                camera.setFocusModeLocked(lensPosition: manualFocusPosition, completionHandler: nil)
            }
            camera.unlockForConfiguration()
            DispatchQueue.main.async {
                self.isManualFocusMode = true
                self.focusMode = .locked
                self.focusState = .locked
            }
        } catch {
            print("Enable manual focus error: \(error)")
        }
    }

    func adjustFocusPosition(_ position: Float) {
        guard let camera = currentCamera, canAdjustFocus, isManualFocusMode else { return }
        let clamped = max(0.0, min(1.0, position))
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.locked) {
                camera.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
            }
            camera.unlockForConfiguration()
        } catch {
            print("Adjust focus position error: \(error)")
        }
    }

    func enableAutoFocusMode() {
        enableContinuousAutoFocus()
        DispatchQueue.main.async {
            self.isManualFocusMode = false
        }
    }

    func getFocusRange() -> (min: Float, max: Float) {
        (0.0, 1.0)
    }

    deinit {
        removeCurrentCameraObservers()
        focusIndicatorTimer?.invalidate()
        longPressTimer?.invalidate()
    }
}

// MARK: - KVO Observer

extension FocusManager {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let camera = object as? AVCaptureDevice else { return }

        DispatchQueue.main.async {
            switch keyPath {
            case "adjustingFocus":
                if camera.isAdjustingFocus {
                    self.focusState = .focusing
                } else {
                    // Focus completed
                    self.focusState = .locked

                    // Notify external focus status changes
                    self.focusStateChangeCallback?(.locked)

                    // Reset state after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self.focusState == .locked, self.focusMode != .locked {
                            self.focusState = .idle
                        }
                    }
                }

            case "lensPosition":
                self.currentLensPosition = camera.lensPosition

            default:
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }
    }
}
