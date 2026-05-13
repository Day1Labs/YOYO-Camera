import AVFoundation
import Combine
import SwiftUI

// MARK: - white balance manager

final class WhiteBalanceManager: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = WhiteBalanceManager()

    // MARK: - Published Properties

    /// manual white balance temperature value
    @Published var manualTemperature: Float = 5500.0 {
        didSet {
            if oldValue != manualTemperature, manualTemperature >= 2000, isManualMode {
                setWhiteBalance(temperature: manualTemperature)
            }
        }
    }

    /// manual white balance tint value
    @Published var manualTint: Float = 0.0

    /// whether manual white balance mode is active
    @Published private(set) var isManualMode: Bool = false

    /// currentwhite balancetemperature(real-timeupdate)
    @Published private(set) var currentTemperature: Float = 5500.0

    /// currentwhite balancetint(real-timeupdate)
    @Published private(set) var currentTint: Float = 0.0

    /// current white balance mode
    @Published private(set) var currentMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance

    /// whether white balance capability is available
    @Published private(set) var isAvailable: Bool = false

    // MARK: - Private Properties

    private var currentCamera: AVCaptureDevice?

    // MARK: - Preview Mode (for testing)

    private var isPreviewMode: Bool = false
    private var previewWhiteBalance: (temperature: Float, tint: Float, mode: AVCaptureDevice.WhiteBalanceMode) = (5500, 0, .continuousAutoWhiteBalance)

    // MARK: - Public Methods

    /// setcurrentcamera
    func setCurrentCamera(_ camera: AVCaptureDevice?) {
        removeObservers()
        currentCamera = camera
        setupObservers()
        updateCapabilities()
        updateCurrentValues()

        // setcamera, ensureinitializationautowhite balancemode
        if camera != nil {
            enableAutoMode()
        }
    }

    /// autowhite balance
    func enableAutoMode() {
        print("[WhiteBalance] Enabling auto mode")

        guard let camera = currentCamera else {
            print("[WhiteBalance] ⚠️ enableAutoMode called but currentCamera is nil")
            // camera, setautomode
            DispatchQueue.main.async {
                self.isManualMode = false
            }
            return
        }

        do {
            try camera.lockForConfiguration()

            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
                print("[WhiteBalance] ✅ Set to continuous auto white balance")
            } else if camera.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                camera.whiteBalanceMode = .autoWhiteBalance
                print("[WhiteBalance] ✅ Set to auto white balance")
            }

            camera.unlockForConfiguration()

            DispatchQueue.main.async {
                self.isManualMode = false
            }
        } catch {
            print("[WhiteBalance] ❌ Failed to enable auto white balance: \(error)")
            // setfailed, update UI state
            DispatchQueue.main.async {
                self.isManualMode = false
            }
        }
    }

    /// manualwhite balancemode
    func enableManualMode() {
        print("[WhiteBalance] Enabling manual mode")
        DispatchQueue.main.async {
            self.isManualMode = true
        }
    }

    /// setwhite balance(temperaturetint)
    /// - Parameters:
    ///   - temperature: temperature (2000K - 8000K)
    ///   - tint: tint (-150 - 150)
    func setWhiteBalance(temperature: Float, tint: Float = 0) {
        guard let camera = currentCamera else {
            print("[WhiteBalance] ⚠️ setWhiteBalance called but currentCamera is nil")
            return
        }

        print("[WhiteBalance] Setting white balance - Temperature: \(temperature)K, Tint: \(tint)")

        do {
            try camera.lockForConfiguration()

            // temperaturetintrange
            let clampedTemperature = max(2000, min(8000, temperature))
            let clampedTint = max(-150, min(150, tint))

            let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: clampedTemperature,
                tint: clampedTint
            )
            let gains = camera.deviceWhiteBalanceGains(for: tempAndTint)

            // devicesupportrange
            let maxGain = camera.maxWhiteBalanceGain
            let minGain: Float = 1.0

            let clampedGains = AVCaptureDevice.WhiteBalanceGains(
                redGain: max(minGain, min(maxGain, gains.redGain)),
                greenGain: max(minGain, min(maxGain, gains.greenGain)),
                blueGain: max(minGain, min(maxGain, gains.blueGain))
            )

            camera.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
            camera.unlockForConfiguration()
        } catch {
            print("[WhiteBalance] ❌ Failed to set white balance: \(error)")
        }
    }

    /// getwhite balancetemperaturerange
    func getTemperatureRange() -> (min: Float, max: Float) {
        // Standard color temperature range: 2000K (candlelight) to 8000K (clear sky)
        (min: 2000.0, max: 8000.0)
    }

    /// getwhite balancetintrange
    func getTintRange() -> (min: Float, max: Float) {
        (min: -150.0, max: 150.0)
    }

    /// getcurrentwhite balanceset(syncmethod, used for)
    func getCurrentWhiteBalance() -> (temperature: Float, tint: Float, mode: AVCaptureDevice.WhiteBalanceMode) {
        if isPreviewMode {
            return previewWhiteBalance
        }
        return (temperature: currentTemperature, tint: currentTint, mode: currentMode)
    }

    /// checkdevicewhethersupportwhite balance
    func isSupported() -> Bool {
        guard let camera = currentCamera else { return false }
        return camera.isWhiteBalanceModeSupported(.locked) &&
            camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
    }

    // MARK: - Preview Mode (for testing)

    /// setpreviewmodewhite balance(used forpreview)
    func setPreviewWhiteBalance(temperature: Float, tint: Float = 0, mode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance) {
        DispatchQueue.main.async {
            self.previewWhiteBalance = (temperature, tint, mode)
            self.isPreviewMode = true
            self.currentTemperature = temperature
            self.currentTint = tint
            self.currentMode = mode
            self.isAvailable = true
        }
    }

    // MARK: - Private Methods

    /// updatewhite balancecapability
    private func updateCapabilities() {
        guard let camera = currentCamera else {
            DispatchQueue.main.async {
                self.isAvailable = false
            }
            return
        }

        let canAdjust = camera.isWhiteBalanceModeSupported(.locked) &&
            camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)

        DispatchQueue.main.async {
            self.isAvailable = canAdjust
        }
    }

    /// updatecurrentwhite balance
    private func updateCurrentValues() {
        guard let camera = currentCamera else {
            DispatchQueue.main.async {
                self.currentTemperature = 5500.0
                self.currentTint = 0.0
                self.currentMode = .continuousAutoWhiteBalance
            }
            return
        }

        let gains = camera.deviceWhiteBalanceGains
        let maxGain = camera.maxWhiteBalanceGain
        let minGain: Float = 1.0

        // checkwhetherrange
        if gains.redGain >= minGain, gains.redGain <= maxGain,
           gains.greenGain >= minGain, gains.greenGain <= maxGain,
           gains.blueGain >= minGain, gains.blueGain <= maxGain
        {
            let tempAndTint = camera.temperatureAndTintValues(for: gains)
            let mode = camera.whiteBalanceMode
            DispatchQueue.main.async {
                // update currentTemperature and currentTint, becausecamerastate
                self.currentTemperature = tempAndTint.temperature
                self.currentTint = tempAndTint.tint
                self.currentMode = mode

                // ifcameramode locked automode, update isManualMode
                if mode != .locked, self.isManualMode {
                    self.isManualMode = false
                }
            }
        } else {
            DispatchQueue.main.async {
                self.currentTemperature = 5500.0
                self.currentTint = 0.0
                self.currentMode = camera.whiteBalanceMode
            }
        }
    }

    /// set
    private func setupObservers() {
        guard let camera = currentCamera else { return }
        camera.addObserver(self, forKeyPath: "deviceWhiteBalanceGains", options: [.new], context: nil)
        camera.addObserver(self, forKeyPath: "whiteBalanceMode", options: [.new], context: nil)
    }

    /// remove
    private func removeObservers() {
        guard let camera = currentCamera else { return }
        camera.removeObserver(self, forKeyPath: "deviceWhiteBalanceGains", context: nil)
        camera.removeObserver(self, forKeyPath: "whiteBalanceMode", context: nil)
    }

    deinit {
        removeObservers()
    }
}

// MARK: - KVO Observer

extension WhiteBalanceManager {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let camera = object as? AVCaptureDevice else { return }

        switch keyPath {
        case "deviceWhiteBalanceGains":
            updateCurrentValues()

        case "whiteBalanceMode":
            DispatchQueue.main.async {
                self.currentMode = camera.whiteBalanceMode
            }

        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}
