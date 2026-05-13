import AVFoundation
import Combine
import SwiftUI

// MARK: - Exposure state enum

enum ExposureState {
    case idle
    case adjusting
    case locked
    case failed
}

// MARK: - Exposure mode enum

enum ExposureMode {
    case auto // autoexposure
    case locked // exposure
    case continuous // autoexposure
}

// MARK: - exposure manager

final class ExposureManager: NSObject, ObservableObject {
    // MARK: -

    static let shared = ExposureManager()

    // MARK: - Published Properties

    @Published private(set) var exposureState: ExposureState = .idle
    @Published var exposureMode: ExposureMode = .auto
    @Published private(set) var exposurePoint: CGPoint = .init(x: 0.5, y: 0.5)
    @Published private(set) var isShowingExposureIndicator: Bool = false
    @Published private(set) var isExposureLocked: Bool = false
    @Published var exposureCompensation: Float = 0.0 {
        didSet {
            if oldValue != exposureCompensation {
                adjustExposureCompensation(exposureCompensation)
            }
        }
    }

    @Published private(set) var canAdjustExposure: Bool = false

    // MARK: - Manual ISO Control

    @Published var manualISO: Float = 0.0 {
        didSet {
            if oldValue != manualISO, manualISO > 0, isManualISOMode {
                adjustISO(manualISO)
            }
        }
    }

    @Published private(set) var canAdjustISO: Bool = false
    @Published private(set) var isManualISOMode: Bool = false
    @Published private(set) var isoRange: (min: Float, max: Float) = (0, 0)

    // MARK: - Manual Shutter Speed Control

    @Published var manualShutterSpeed: Double = 0.0 {
        didSet {
            if oldValue != manualShutterSpeed, manualShutterSpeed > 0, isManualShutterSpeedMode {
                adjustShutterSpeed(manualShutterSpeed)
            }
        }
    }

    @Published private(set) var canAdjustShutterSpeed: Bool = false
    @Published private(set) var isManualShutterSpeedMode: Bool = false
    @Published private(set) var shutterSpeedRange: (min: Double, max: Double) = (0, 0)

    // MARK: - cameraparametersreal-time

    @Published private(set) var currentAperture: Float = 0.0 // aperture (f)
    @Published private(set) var currentShutterSpeed: Double = 0.0 // shutter speed ()
    @Published private(set) var currentISO: Float = 0.0 // ISO
    @Published private(set) var isParametersAvailable: Bool = false // parameterswhetheravailable

    // MARK: - Private Properties

    private var currentCamera: AVCaptureDevice?
    private var previewSize: CGSize = .zero
    private var previewOrigin: CGPoint = .zero
    private var exposureIndicatorTimer: Timer?

    private var exposureStateChangeCallback: ((ExposureState) -> Void)?

    override private init() {
        super.init()
    }

    func setPreviewParameters(aperture: Float = 2.4, shutterSpeed: Double = 1.0 / 60.0, iso: Float = 100, isLocked: Bool = false, compensation: Float = 0.0) {
        DispatchQueue.main.async {
            self.currentAperture = aperture
            self.currentShutterSpeed = shutterSpeed
            self.currentISO = iso
            self.isParametersAvailable = true
            self.isExposureLocked = isLocked
            self.exposureCompensation = compensation
        }
    }

    func setCurrentCamera(_ camera: AVCaptureDevice?) {
        removeCurrentCameraObservers()
        currentCamera = camera
        setupCameraObservers()
        updateExposureCapability()

        // setcamera, ensureinitializationautomode
        if camera != nil {
            // autoexposuremode
            enableContinuousAutoExposure()

            // ensure ISO shutter speedautomode
            DispatchQueue.main.async {
                self.isManualISOMode = false
                self.isManualShutterSpeedMode = false
            }
        }
    }

    func setPreviewSize(_ size: CGSize) {
        previewSize = size
    }

    func setPreviewFrame(_ frame: CGRect) {
        previewOrigin = frame.origin
        previewSize = frame.size
    }

    func setExposureStateChangeCallback(_ callback: @escaping (ExposureState) -> Void) {
        exposureStateChangeCallback = callback
    }

    /// setexposure
    func setExposure(at point: CGPoint) {
        guard let camera = currentCamera,
              camera.isExposurePointOfInterestSupported else { return }

        let devicePoint = convertPointToDeviceCoordinates(point)

        do {
            try camera.lockForConfiguration()

            // setexposure
            camera.exposurePointOfInterest = devicePoint

            // setexposuremode
            if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.exposurePoint = point
                self.showExposureIndicator()
                self.exposureState = .adjusting
            }

        } catch {
            print("Set exposure error: \(error)")
            DispatchQueue.main.async {
                self.exposureState = .failed
            }
        }
    }

    /// currentexposure
    func lockExposure() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // exposure
            if camera.isExposureModeSupported(.locked) {
                camera.exposureMode = .locked
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.isExposureLocked = true
                self.exposureMode = .locked
                self.exposureState = .locked
            }

        } catch {
            print("Exposure Lock error: \(error)")
        }
    }

    /// exposure
    func unlockExposure() {
        guard let camera = currentCamera, isExposureLocked else { return }

        do {
            try camera.lockForConfiguration()

            // restoreautoexposure
            if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.isExposureLocked = false
                self.exposureMode = .auto
                self.exposureState = .idle
                self.hideExposureIndicator()
            }

        } catch {
            print("Exposure Unlock error: \(error)")
        }
    }

    /// switchexposurestate
    func toggleExposureLock() {
        if isExposureLocked {
            unlockExposure()
        } else {
            lockExposure()
        }
    }

    /// exposure
    func adjustExposureCompensation(_ value: Float) {
        guard let camera = currentCamera,
              canAdjustExposure else { return }

        let clampedValue = max(camera.minExposureTargetBias,
                               min(camera.maxExposureTargetBias, value))

        do {
            try camera.lockForConfiguration()
            camera.setExposureTargetBias(clampedValue, completionHandler: nil)
            camera.unlockForConfiguration()

        } catch {
            print("Exposure compensation error: \(error)")
        }
    }

    /// setautoexposure
    func enableContinuousAutoExposure() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // setautoexposure
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.exposureMode = .continuous
                self.exposureState = .idle
            }

        } catch {
            print("Continuous exposure setup error: \(error)")
        }
    }

    /// autoexposure
    func disableContinuousAutoExposure() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // switchautoexposuremode
            if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.exposureMode = .auto
            }

        } catch {
            print("Disable continuous exposure error: \(error)")
        }
    }

    func resetExposureToCenter() {
        let centerPoint = CGPoint(x: previewOrigin.x + previewSize.width / 2,
                                  y: previewOrigin.y + previewSize.height / 2)
        setExposure(at: centerPoint)
    }

    /// checkwhethersupportexposure
    func supportsExposureCompensation() -> Bool {
        guard let camera = currentCamera else { return false }
        return camera.minExposureTargetBias < camera.maxExposureTargetBias
    }

    /// getexposurerange
    func getExposureCompensationRange() -> (min: Float, max: Float) {
        guard let camera = currentCamera else { return (0, 0) }
        return (camera.minExposureTargetBias, camera.maxExposureTargetBias)
    }

    /// ISO
    func adjustISO(_ iso: Float) {
        guard let camera = currentCamera,
              canAdjustISO else { return }

        let minISO = camera.activeFormat.minISO
        let maxISO = camera.activeFormat.maxISO
        let clampedISO = max(minISO, min(maxISO, iso))

        do {
            try camera.lockForConfiguration()
            camera.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: clampedISO) { _ in }
            camera.unlockForConfiguration()
        } catch {
            print("ISO adjustment error: \(error)")
        }
    }

    /// shutter speed
    func adjustShutterSpeed(_ shutterSpeed: Double) {
        guard let camera = currentCamera,
              canAdjustShutterSpeed else { return }

        let minDuration = CMTimeGetSeconds(camera.activeFormat.minExposureDuration)
        let maxDuration = CMTimeGetSeconds(camera.activeFormat.maxExposureDuration)
        let clampedDuration = max(minDuration, min(maxDuration, shutterSpeed))
        let duration = CMTimeMakeWithSeconds(clampedDuration, preferredTimescale: 1_000_000_000)

        do {
            try camera.lockForConfiguration()
            camera.setExposureModeCustom(duration: duration, iso: AVCaptureDevice.currentISO) { _ in }
            camera.unlockForConfiguration()
        } catch {
            print("Shutter speed adjustment error: \(error)")
        }
    }

    /// switchmanual ISO mode
    func enableManualISO() {
        // syncset, currentISO onChange callback
        isManualISOMode = true
    }

    /// switchauto ISO mode
    func enableAutoISO() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // restoreautoexposuremode
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            } else if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.isManualISOMode = false
            }
        } catch {
            print("Enable auto ISO error: \(error)")
        }
    }

    /// switchmanualshutter speedmode
    func enableManualShutterSpeed() {
        // syncset, currentShutterSpeed onChange callback
        isManualShutterSpeedMode = true
    }

    /// switchautoshutter speedmode
    func enableAutoShutterSpeed() {
        guard let camera = currentCamera else { return }

        do {
            try camera.lockForConfiguration()

            // restoreautoexposuremode
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            } else if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.isManualShutterSpeedMode = false
            }
        } catch {
            print("Enable auto shutter speed error: \(error)")
        }
    }

    /// get ISO range
    func getISORange() -> (min: Float, max: Float) {
        isoRange
    }

    /// getshutter speedrange
    func getShutterSpeedRange() -> (min: Double, max: Double) {
        shutterSpeedRange
    }

    /// checkcurrentdevicewhethersupportexposure
    func isExposureSupported() -> Bool {
        guard let camera = currentCamera else { return false }
        return camera.isExposurePointOfInterestSupported ||
            camera.isExposureModeSupported(.autoExpose) ||
            camera.isExposureModeSupported(.continuousAutoExposure)
    }

    /// getcurrentdevicesupportexposuremode
    func getSupportedExposureModes() -> [ExposureMode] {
        guard let camera = currentCamera else { return [] }

        var supportedModes: [ExposureMode] = []

        if camera.isExposureModeSupported(.autoExpose) {
            supportedModes.append(.auto)
        }

        if camera.isExposureModeSupported(.continuousAutoExposure) {
            supportedModes.append(.continuous)
        }

        if camera.isExposureModeSupported(.locked) {
            supportedModes.append(.locked)
        }

        return supportedModes
    }

    // MARK: - Private Methods

    /// updateexposurefeaturesavailable
    private func updateExposureCapability() {
        guard let camera = currentCamera else {
            DispatchQueue.main.async {
                self.canAdjustExposure = false
                self.canAdjustISO = false
                self.isoRange = (0, 0)
            }
            return
        }
        let canAdjust = camera.minExposureTargetBias < camera.maxExposureTargetBias
        let minISO = camera.activeFormat.minISO
        let maxISO = camera.activeFormat.maxISO
        let canAdjustISO = maxISO > minISO

        let minDuration = CMTimeGetSeconds(camera.activeFormat.minExposureDuration)
        let maxDuration = CMTimeGetSeconds(camera.activeFormat.maxExposureDuration)
        let canAdjustShutterSpeed = maxDuration > minDuration

        DispatchQueue.main.async {
            self.canAdjustExposure = canAdjust
            self.canAdjustISO = canAdjustISO
            self.isoRange = (minISO, maxISO)
            self.manualISO = camera.iso

            self.canAdjustShutterSpeed = canAdjustShutterSpeed
            self.shutterSpeedRange = (minDuration, maxDuration)
            self.manualShutterSpeed = CMTimeGetSeconds(camera.exposureDuration)
        }
    }

    /// setcamera
    private func setupCameraObservers() {
        guard let camera = currentCamera else { return }

        // observeexposurestate
        camera.addObserver(self, forKeyPath: "adjustingExposure", options: [.new], context: nil)

        // observecameraparameters
        camera.addObserver(self, forKeyPath: "lensAperture", options: [.new], context: nil)
        camera.addObserver(self, forKeyPath: "exposureDuration", options: [.new], context: nil)
        camera.addObserver(self, forKeyPath: "ISO", options: [.new], context: nil)

        // initializationparameters
        updateCameraParameters()
    }

    /// removecurrentcamera
    private func removeCurrentCameraObservers() {
        guard let camera = currentCamera else { return }

        camera.removeObserver(self, forKeyPath: "adjustingExposure", context: nil)
        camera.removeObserver(self, forKeyPath: "lensAperture", context: nil)
        camera.removeObserver(self, forKeyPath: "exposureDuration", context: nil)
        camera.removeObserver(self, forKeyPath: "ISO", context: nil)
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

    /// exposureindicator
    private func showExposureIndicator() {
        isShowingExposureIndicator = true

        // timer
        exposureIndicatorTimer?.invalidate()

        // exposureindicatormode
        if exposureMode != .locked {
            exposureIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.isShowingExposureIndicator = false
                }
            }
        }
    }

    /// updatecameraparameters
    private func updateCameraParameters() {
        guard let camera = currentCamera else {
            DispatchQueue.main.async {
                self.currentAperture = 0.0
                self.currentShutterSpeed = 0.0
                self.currentISO = 0.0
                self.isParametersAvailable = false
            }
            return
        }

        DispatchQueue.main.async {
            self.currentAperture = camera.lensAperture
            self.currentShutterSpeed = CMTimeGetSeconds(camera.exposureDuration)
            self.currentISO = camera.iso
            self.isParametersAvailable = true
        }
    }

    /// exposureindicator
    private func hideExposureIndicator() {
        exposureIndicatorTimer?.invalidate()
        isShowingExposureIndicator = false
    }

    deinit {
        removeCurrentCameraObservers()
        exposureIndicatorTimer?.invalidate()
    }
}

// MARK: - KVO Observer

extension ExposureManager {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let camera = object as? AVCaptureDevice else { return }

        DispatchQueue.main.async {
            switch keyPath {
            case "adjustingExposure":
                if camera.isAdjustingExposure {
                    self.exposureState = .adjusting
                } else {
                    // exposurecomplete
                    self.exposureState = .locked

                    // notifyexposurestate
                    self.exposureStateChangeCallback?(.locked)

                    // delayresetstate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self.exposureState == .locked, self.exposureMode != .locked {
                            self.exposureState = .idle
                        }
                    }
                }

            case "exposureDuration":
                // shutter speed
                self.currentShutterSpeed = CMTimeGetSeconds(camera.exposureDuration)
                self.isParametersAvailable = true

            case "ISO":
                // ISO
                self.currentISO = camera.iso
                self.isParametersAvailable = true

            case "lensAperture":
                // aperture
                self.currentAperture = camera.lensAperture
                self.isParametersAvailable = true

            default:
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }
    }
}
