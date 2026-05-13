import AVFoundation
import Combine
import SwiftUI

// MARK: - ZoomManager

/// managementcamerazoomlogic, interfacezoom, devicezoom, deviceswitch
final class ZoomManager: ObservableObject {
    // MARK: - Singleton

    static let shared = ZoomManager()

    // MARK: - Constants

    /// maximum zoom factor limit
    private static let maxZoomLimit: Double = 10.0

    // MARK: - Published Properties

    @Published private(set) var deviceZoomFactor: Double = 1.0
    @Published private(set) var isDeviceSwitching: Bool = false
    @Published private(set) var zoomRange: (min: Double, max: Double) = (min: 1.0, max: 10.0)

    // MARK: - Private Properties

    private var availableDevices: [AVCaptureDevice.DeviceType: CameraDeviceCapability] = [:]
    private var deviceSwitchCallback: ((AVCaptureDevice.DeviceType, AVCaptureDevice.Position, Double) -> Void)?
    // devicereference(referencereference)
    private weak var currentCamera: AVCaptureDevice?
    private weak var ultraWideCamera: AVCaptureDevice?
    private weak var wideAngleCamera: AVCaptureDevice?
    private weak var telephotoCamera: AVCaptureDevice?

    // MARK: - Initialization

    private init() {
        setupDeviceCapabilities()
    }

    // MARK: - Public Methods

    /// set available camera devices
    func setAvailableCameras(current: AVCaptureDevice?, ultraWide: AVCaptureDevice?, wide: AVCaptureDevice?, telephoto: AVCaptureDevice?) {
        currentCamera = current
        ultraWideCamera = ultraWide
        wideAngleCamera = wide
        telephotoCamera = telephoto

        setupDeviceCapabilities()
        // No longer using cutover thresholds for auto-switching

        // updatezoomrange
        updateZoomRange()
    }

    /// set the current camera device
    func setCurrentCamera(_ camera: AVCaptureDevice?, deviceType: AVCaptureDevice.DeviceType) {
        print("[Zoom Debug] 🎥 setCurrentCamera - deviceType: \(deviceType.rawValue)")

        guard currentCamera?.deviceType != deviceType || currentCamera !== camera else {
            return
        }

        currentCamera = camera

        if let camera {
            updateDeviceCapability(for: deviceType, camera: camera)
            // Sync device zoom factor from camera
            deviceZoomFactor = Double(camera.videoZoomFactor)
        }

        updateZoomRange()
    }

    /// set the device zoom factor directly (core method)
    /// - Parameters:
    ///   - factor: target device zoom factor (1.0x...)
    func setZoomFactor(_ factor: Double) {
        guard let camera = currentCamera else { return }

        let capability = getCurrentDeviceCapability()
        let maxZoom = min(capability.maxDeviceZoom, Self.maxZoomLimit)
        let clamped = max(capability.minDeviceZoom, min(maxZoom, factor))

        // Update state
        deviceZoomFactor = clamped

        // Apply to hardware
        do {
            try camera.lockForConfiguration()
            camera.videoZoomFactor = CGFloat(clamped)
            camera.unlockForConfiguration()
        } catch {
            print("[ZoomManager] Failed to set zoom factor: \(error)")
        }
    }

    func resetZoom() {
        setZoomFactor(1.0)
    }

    func syncZoomFactorFromCamera() {
        guard let camera = currentCamera else { return }
        let current = Double(camera.videoZoomFactor)
        if Thread.isMainThread {
            deviceZoomFactor = current
        } else {
            DispatchQueue.main.async {
                self.deviceZoomFactor = current
            }
        }
    }

    /// switch devices manually (manual lens switch)
    /// - Parameter deviceType: target device type
    func switchToDevice(_ deviceType: AVCaptureDevice.DeviceType) {
        guard !isDeviceSwitching else { return }
        // Prevent switching to same device type if already active (unless position differs, handled by Manager)
        if currentCamera?.deviceType == deviceType, currentCamera?.position == .back {
            print("[ZoomManager] Already on device \(deviceType.rawValue), resetting zoom to 1.0")
            resetZoom()
            return
        }

        print("[ZoomManager] Requesting switch to \(deviceType.rawValue)")
        isDeviceSwitching = true

        // Calculate target interface zoom based on device capability
        // We want the device zoom factor to be 1.0 (native field of view)
        let targetDeviceZoom = 1.0

        // Switch and reset zoom to the calculated interface zoom
        deviceSwitchCallback?(deviceType, .back, targetDeviceZoom)
    }

    /// ... keep existing gesture helper if useful, or adapt it ...
    func applyGestureZoom(_ zoomDelta: Double, baseZoom: Double, allowDeviceSwitch _: Bool = true) {
        // baseZoom here is likely deviceZoomFactor in the new model
        let newZoom = baseZoom * zoomDelta
        setZoomFactor(newZoom)
    }

    /// set the device-switch callback
    func setDeviceSwitchCallback(_ callback: @escaping (AVCaptureDevice.DeviceType, AVCaptureDevice.Position, Double) -> Void) {
        deviceSwitchCallback = callback
    }

    /// confirm that device switching is complete
    func confirmDeviceSwitchCompleted(deviceType: AVCaptureDevice.DeviceType, camera: AVCaptureDevice) {
        DispatchQueue.main.async {
            self.isDeviceSwitching = false
            self.currentCamera = camera
            self.updateDeviceCapability(for: deviceType, camera: camera)
            self.updateZoomRange()

            self.resetZoom()
            print("[ZoomManager] Device switch confirmed. Zoom reset to 1.0x")
        }
    }

    /// get current device capabilities
    func getCurrentDeviceCapability() -> CameraDeviceCapability {
        availableDevices[currentCamera?.deviceType ?? .builtInWideAngleCamera] ?? CameraDeviceCapability.defaultCapability
    }

    // MARK: - Private / Helper

    private func updateZoomRange() {
        let capability = getCurrentDeviceCapability()
        // Range is now strictly the device's capability, capped at maxZoomLimit
        let newRange = (min: capability.minDeviceZoom, max: min(capability.maxDeviceZoom, Self.maxZoomLimit))

        if zoomRange.min != newRange.min || zoomRange.max != newRange.max {
            zoomRange = newRange
            print("[ZoomManager] Range updated to [\(newRange.min), \(newRange.max)]")
        }
    }

    /// calculate the current focal length
    func calculateCurrentFocalLength(deviceSpec: CameraDeviceCameraSpec, currentCameraDeviceType: CameraDeviceType) -> Double {
        let baseFocalLength: Double
        switch currentCameraDeviceType {
        case .ultraWide:
            baseFocalLength = deviceSpec.ultraWideFocalLength ?? 13.0
        case .backWide:
            baseFocalLength = deviceSpec.wideFocalLength
        case .telephoto:
            baseFocalLength = deviceSpec.telephotoFocalLength ?? 77.0
        case .frontWide:
            baseFocalLength = deviceSpec.wideFocalLength
        }
        return baseFocalLength * deviceZoomFactor
    }

    // MARK: - Private Methods

    /// set device capabilities
    private func setupDeviceCapabilities() {
        let types: [AVCaptureDevice.DeviceType] = [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back)

        availableDevices.removeAll()

        for device in discovery.devices {
            let minDev = Double(device.minAvailableVideoZoomFactor)
            let maxDev = min(Double(device.maxAvailableVideoZoomFactor), Double(device.activeFormat.videoMaxZoomFactor), Self.maxZoomLimit)

            availableDevices[device.deviceType] = CameraDeviceCapability(
                deviceType: device.deviceType,
                minDeviceZoom: minDev,
                maxDeviceZoom: maxDev
            )
        }
    }

    /// update device capabilities
    private func updateDeviceCapability(for deviceType: AVCaptureDevice.DeviceType, camera: AVCaptureDevice) {
        guard var capability = availableDevices[deviceType] else { return }

        let newMinDeviceZoom = Double(camera.minAvailableVideoZoomFactor)
        let newMaxDeviceZoom = min(Double(camera.maxAvailableVideoZoomFactor), Double(camera.activeFormat.videoMaxZoomFactor), Self.maxZoomLimit)

        if capability.minDeviceZoom == newMinDeviceZoom, capability.maxDeviceZoom == newMaxDeviceZoom {
            return
        }

        capability.minDeviceZoom = newMinDeviceZoom
        capability.maxDeviceZoom = newMaxDeviceZoom

        availableDevices[deviceType] = capability
    }

    /// zoomdevice(sync, used fordeviceswitchzoom)
    func applyZoomImmediately(to device: AVCaptureDevice, deviceZoom: Double) {
        let clampedZoom = max(0.5, min(Self.maxZoomLimit, deviceZoom))

        let minDev = Double(device.minAvailableVideoZoomFactor)
        let maxDev = min(Double(device.maxAvailableVideoZoomFactor), Double(device.activeFormat.videoMaxZoomFactor), Self.maxZoomLimit)
        let clampedDeviceZoom = max(minDev, min(maxDev, clampedZoom))

        print("[Zoom Debug] ⚡ applyZoomImmediately to \(device.deviceType.rawValue):")
        print("  - Device zoom: \(String(format: "%.3f", clampedDeviceZoom))x")

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(clampedDeviceZoom)
            device.unlockForConfiguration()
            print("[Zoom Debug] ✅ Immediate zoom set successfully")
        } catch {
            print("[Zoom Debug] ❌ Failed to set immediate zoom: \(error)")
        }
    }
}
