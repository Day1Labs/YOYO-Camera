import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - logicdevice, / wide

enum CameraDeviceType: String, CaseIterable, Identifiable {
    case frontWide
    case backWide
    case ultraWide
    case telephoto
    var id: String { rawValue }
}

// MARK: - devicecapability

struct CameraDeviceCapability {
    let deviceType: AVCaptureDevice.DeviceType
    var minDeviceZoom: Double
    var maxDeviceZoom: Double

    static let defaultCapability = CameraDeviceCapability(
        deviceType: .builtInWideAngleCamera,
        minDeviceZoom: 1.0,
        maxDeviceZoom: 3.0
    )
}

final class CameraDeviceManager: NSObject, ObservableObject {
    // MARK: -

    static let shared = CameraDeviceManager()

    // MARK: - devicemanagementproperties

    private(set) var currentCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    private var backCamera: AVCaptureDevice?
    private var ultraWideCamera: AVCaptureDevice?
    private var wideAngleCamera: AVCaptureDevice?
    private var telephotoCamera: AVCaptureDevice?
    private var currentBackDeviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera

    // MARK: - Manager References

    private var focusManager: FocusManager { .shared }
    private var exposureManager: ExposureManager { .shared }

    // MARK: - CameraDeviceManager and

    @Published var currentCameraDeviceType: CameraDeviceType = .backWide

    // MARK: - white balance manager

    let whiteBalanceManager = WhiteBalanceManager.shared

    // MARK: - zoommanager

    let zoomManager = ZoomManager.shared

    // MARK: - initialization

    override private init() {
        super.init()
        setupDevices()
        setupDefaultDeviceSwitchCallback()
    }

    // MARK: - devicemanagementmethod

    func setupDevices() {
        // 1. camera
        let frontDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .front
        )
        frontCamera = frontDiscovery.devices.first

        // 2. device
        var backTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(iOS 13.0, *) { backTypes.append(.builtInUltraWideCamera) }
        if #available(iOS 10.2, *) { backTypes.append(.builtInTelephotoCamera) }
        let backDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: backTypes,
            mediaType: .video,
            position: .back
        )
        let backDevices = backDiscovery.devices

        ultraWideCamera = backDevices.first { $0.deviceType == .builtInUltraWideCamera }
        wideAngleCamera = backDevices.first { $0.deviceType == .builtInWideAngleCamera }
        telephotoCamera = backDevices.first { $0.deviceType == .builtInTelephotoCamera }

        // 3. setcamera
        backCamera = wideAngleCamera ?? telephotoCamera ?? ultraWideCamera
        currentCamera = backCamera
        if let cam = currentCamera {
            currentBackDeviceType = cam.deviceType
        }
        print("📷 [DeviceManager] 使用设备: \(currentCamera?.deviceType.rawValue ?? "nil")")

        // synccamerawhite balance manager
        whiteBalanceManager.setCurrentCamera(currentCamera)

        // synccamerazoommanager
        zoomManager.setAvailableCameras(
            current: currentCamera,
            ultraWide: ultraWideCamera,
            wide: wideAngleCamera,
            telephoto: telephotoCamera
        )
    }

    func switchCameraPosition() {
        let isCurrentlyBackCamera = currentCamera == backCamera || currentCamera?.position == .back
        if isCurrentlyBackCamera {
            currentCamera = frontCamera
        } else {
            // switch: usedevice
            currentCamera = backCamera // backCamera device(ifavailable)
            if let cam = currentCamera {
                currentBackDeviceType = cam.deviceType
            }
        }

        // synccamerawhite balance manager
        whiteBalanceManager.setCurrentCamera(currentCamera)
    }

    func getCurrentCamera() -> AVCaptureDevice? {
        currentCamera
    }

    func getAvailableCameras() -> [AVCaptureDevice] {
        var cameras: [AVCaptureDevice] = []
        if let front = frontCamera { cameras.append(front) }
        if let back = backCamera { cameras.append(back) }
        if let ultra = ultraWideCamera { cameras.append(ultra) }
        if let wide = wideAngleCamera, wide != backCamera { cameras.append(wide) }
        if let tele = telephotoCamera { cameras.append(tele) }
        return cameras
    }

    func getCurrentBackDeviceType() -> AVCaptureDevice.DeviceType {
        currentBackDeviceType
    }

    /// Generic accessor for camera by logical device type
    func camera(for type: CameraDeviceType) -> AVCaptureDevice? {
        switch type {
        case .frontWide: return frontCamera
        case .backWide: return backCamera
        case .ultraWide: return ultraWideCamera
        case .telephoto: return telephotoCamera
        }
    }

    // Legacy getters
    func getUltraWideCamera() -> AVCaptureDevice? { camera(for: .ultraWide) }
    func getWideAngleCamera() -> AVCaptureDevice? { camera(for: .backWide) }
    func getTelephotoCamera() -> AVCaptureDevice? { camera(for: .telephoto) }
    func getFrontCamera() -> AVCaptureDevice? { camera(for: .frontWide) }

    /// method: setcurrentcameraandnotifymanager
    /// camerastateupdatelogic
    private func applyCameraState(_ camera: AVCaptureDevice) {
        currentCamera = camera
        whiteBalanceManager.setCurrentCamera(camera)

        zoomManager.setCurrentCamera(camera, deviceType: camera.deviceType)

        let cam = camera
        DispatchQueue.main.async {
            FocusManager.shared.setCurrentCamera(cam)
            ExposureManager.shared.setCurrentCamera(cam)
        }
    }

    /// setcurrentcameramethod(compatibilityinterface)
    /// use applyCameraState
    func setCurrentCamera(_ camera: AVCaptureDevice) {
        applyCameraState(camera)
    }

    func setCurrentBackDeviceType(_ deviceType: AVCaptureDevice.DeviceType) {
        currentBackDeviceType = deviceType
    }

    // MARK: - zoomrelatedproperties(ZoomManager)

    /// devicezoom(physicaldevice)
    var deviceZoomFactor: Double {
        zoomManager.deviceZoomFactor
    }

    /// deviceswitchstate
    var isDeviceSwitching: Bool {
        zoomManager.isDeviceSwitching
    }

    /// currentfocal length
    var currentFocalLength: Double {
        let deviceSpec = currentDeviceSpec
        return zoomManager.calculateCurrentFocalLength(deviceSpec: deviceSpec, currentCameraDeviceType: currentCameraDeviceType)
    }

    /// currentphysicalfocal length
    var currentPhysicalFocalLength: Double {
        let deviceSpec = currentDeviceSpec
        let basePhysicalFocalLength: Double
        switch currentCameraDeviceType {
        case .ultraWide:
            basePhysicalFocalLength = deviceSpec.ultraWidePhysicalFocalLength ?? 2.22
        case .backWide:
            basePhysicalFocalLength = deviceSpec.widePhysicalFocalLength ?? 6.765
        case .telephoto:
            basePhysicalFocalLength = deviceSpec.telephotoPhysicalFocalLength ?? 15.66
        case .frontWide:
            basePhysicalFocalLength = deviceSpec.widePhysicalFocalLength ?? 6.765
        }
        return basePhysicalFocalLength * deviceZoomFactor
    }

    /// currentdevice
    var currentDeviceSpec: CameraDeviceCameraSpec {
        CameraSpecs.getCurrentDeviceSpec()
    }

    // MARK: - deviceswitchrelatedmethod

    func toggleCameraPosition() {
        let targetPosition: AVCaptureDevice.Position = (currentCamera?.position == .back) ? .front : .back
        switchTo(position: targetPosition)
    }

    func switchTo(position: AVCaptureDevice.Position) {
        let targetDeviceType: AVCaptureDevice.DeviceType = (position == .front) ? .builtInWideAngleCamera : currentBackDeviceType
        let targetZoom = zoomManager.deviceZoomFactor
        handleDeviceSwitch(to: targetDeviceType, position: position, targetZoom: targetZoom)
    }

    /// syncswitchmethod(used forneed to getresult)
    func switchToSync(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let targetDeviceType: AVCaptureDevice.DeviceType = (position == .front) ? .builtInWideAngleCamera : currentBackDeviceType

        // camera
        guard let camera = resolveCamera(for: targetDeviceType, position: position) else {
            print("[DeviceManager] ⚠️ 无法获取目标设备")
            return nil
        }

        // updatecameradevice
        if position == .back {
            currentBackDeviceType = targetDeviceType
        }

        // syncupdatestate
        completeSwitchWithCamera(camera, deviceType: targetDeviceType)

        return camera
    }

    /// setdefaultdeviceswitchcallback(initialization)
    private func setupDefaultDeviceSwitchCallback() {
        zoomManager.setDeviceSwitchCallback { [weak self] deviceType, position, targetZoom in
            self?.handleDeviceSwitch(to: deviceType, position: position, targetZoom: targetZoom)
        }
    }

    /// updatecamerastate(deviceswitchcomplete)
    private func updateCameraState(camera: AVCaptureDevice?, deviceType: AVCaptureDevice.DeviceType) {
        print("[Camera Switch] 📝 updateCameraState - BEFORE: currentCamera position = \(currentCamera?.position == .front ? "Front" : currentCamera?.position == .back ? "Back" : "nil")")

        guard let camera else {
            currentCamera = nil
            whiteBalanceManager.setCurrentCamera(nil)
            zoomManager.setCurrentCamera(nil, deviceType: deviceType)
            return
        }

        // updatecameradevice
        if camera.position == .back {
            currentBackDeviceType = deviceType
        }

        // updatecurrentcameradevice
        currentCameraDeviceType = camera.cameraDeviceType

        print("[Camera Switch] 📝 updateCameraState - AFTER: currentCamera position = \(camera.position == .front ? "Front" : "Back"), deviceType = \(camera.cameraDeviceType.rawValue)")

        // ✅ camerastate(set)
        applyCameraState(camera)
    }

    /// deviceswitch(ZoomManager callback)
    /// camera, updatestate, andnotify session switch
    private func handleDeviceSwitch(to deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position, targetZoom: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // deviceswitch
            let deviceName: String
            switch (deviceType, position) {
            case (.builtInWideAngleCamera, .front):
                deviceName = "前置"
            case (.builtInWideAngleCamera, .back):
                deviceName = "主摄"
            case (.builtInUltraWideCamera, _):
                deviceName = "超广角"
            case (.builtInTelephotoCamera, _):
                deviceName = "长焦"
            default:
                deviceName = "未知"
            }
            print("[DeviceManager] 🎬 选择相机: \(deviceName) (\(deviceType.rawValue)), 位置: \(position == .front ? "Front" : "Back"), 目标缩放: \(String(format: "%.2f", targetZoom))x")

            // cameradevice
            guard let camera = self.resolveCamera(for: deviceType, position: position) else {
                print("[DeviceManager] ⚠️ 无法获取目标设备，回退到当前设备")
                if let fallbackCamera = self.currentCamera {
                    self.completeSwitchWithCamera(fallbackCamera, deviceType: fallbackCamera.deviceType)
                }
                return
            }

            // checkwhetherneed to switch(switchdevice)
            if self.currentCamera === camera {
                print("[DeviceManager] ⏭️ 目标相机与当前相机相同，跳过切换")
                // not switch, complete, let ZoomManager zoom
                self.zoomManager.confirmDeviceSwitchCompleted(deviceType: deviceType, camera: camera)
                return
            }

            // updatecameradevice
            if position == .back {
                self.currentBackDeviceType = deviceType
            }

            // updatestateandtriggercameraswitch
            self.completeSwitchWithCamera(camera, deviceType: deviceType)

            // ✅ notify session cameraswitch
            self.notifySessionToSwitchCamera(camera, targetZoom: targetZoom)
        }
    }

    /// notify session manager switchcamera
    private func notifySessionToSwitchCamera(_ camera: AVCaptureDevice, targetZoom: Double) {
        // notifytrigger session switch, dependencies SessionManager
        NotificationCenter.default.post(
            name: .deviceManagerRequestsCameraSwitch,
            object: camera,
            userInfo: ["targetZoom": targetZoom]
        )
    }

    /// completedeviceswitch, updatestate
    private func completeSwitchWithCamera(_ camera: AVCaptureDevice, deviceType: AVCaptureDevice.DeviceType) {
        print("[Camera Switch] 🎯 completeSwitchWithCamera - deviceType: \(deviceType.rawValue), actual position: \(camera.position == .front ? "Front" : "Back")")
        updateCameraState(camera: camera, deviceType: deviceType)
        zoomManager.confirmDeviceSwitchCompleted(deviceType: deviceType, camera: camera)
        print("[Camera Switch] ✅ completeSwitchWithCamera 完成")
    }

    private func resolveCamera(for deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        print("[Camera Switch] 🔍 resolveCamera - deviceType: \(deviceType.rawValue), position: \(position == .front ? "Front" : "Back")")

        if position == .front {
            let camera = frontCamera ?? discoverDevice(deviceTypes: [.builtInWideAngleCamera], position: .front)
            print("[Camera Switch] 🔍 前置相机: \(camera != nil ? "找到" : "未找到"), position: \(camera?.position == .front ? "Front" : camera?.position == .back ? "Back" : "Unknown")")
            return camera
        }

        let camera: AVCaptureDevice?
        switch deviceType {
        case .builtInUltraWideCamera:
            camera = ultraWideCamera ?? discoverDevice(deviceTypes: [.builtInUltraWideCamera], position: .back) ?? backCamera
        case .builtInTelephotoCamera:
            camera = telephotoCamera ?? discoverDevice(deviceTypes: [.builtInTelephotoCamera], position: .back) ?? backCamera
        case .builtInWideAngleCamera:
            fallthrough
        default:
            camera = wideAngleCamera ?? discoverDevice(deviceTypes: [.builtInWideAngleCamera], position: .back) ?? backCamera
        }

        print("[Camera Switch] 🔍 后置相机: \(camera != nil ? "找到" : "未找到"), position: \(camera?.position == .front ? "Front" : camera?.position == .back ? "Back" : "Unknown")")
        return camera
    }

    private func discoverDevice(deviceTypes: [AVCaptureDevice.DeviceType], position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: position).devices.first
    }

    func setExposureBias(_ bias: Float) {
        guard let camera = currentCamera else {
            print("❌ [DEBUG] setExposureBias: currentCamera 为 nil")
            return
        }

        print("🎯 [DEBUG] setExposureBias 被调用:")
        print("   - 目标 bias: \(bias)")
        print("   - 相机: \(camera.deviceType.rawValue)")

        do {
            try camera.lockForConfiguration()
            let minBias = camera.minExposureTargetBias
            let maxBias = camera.maxExposureTargetBias
            let clampedBias = max(minBias, min(maxBias, bias))

            print("   - 设备支持范围: [\(minBias), \(maxBias)]")
            print("   - 限制后的值: \(clampedBias)")
            print("   - 当前曝光模式: \(camera.exposureMode.rawValue)")

            camera.setExposureTargetBias(clampedBias) { time in
                print("   - ✅ setExposureTargetBias 完成回调, time: \(time)")
            }

            camera.unlockForConfiguration()

            // validatewhethersetsuccessfully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("   - 🔍 验证: 当前设备 exposureTargetBias = \(camera.exposureTargetBias)")
                print("   - 🔍 验证: 当前设备 exposureTargetOffset = \(camera.exposureTargetOffset)")
            }
        } catch {
            print("❌ Failed to set exposure bias: \(error)")
        }
    }

    func setTorch(enabled: Bool) {
        guard let device = currentCamera, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if enabled {
                let level = AVCaptureDevice.maxAvailableTorchLevel
                if device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: level)
                }
            } else {
                if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to set torch: \(error)")
        }
    }

    // MARK: - AI modecameraparametersmethod

    /// set
    func setFocusPoint(_ point: CGPoint) {
        guard let camera = currentCamera else { return }
        do {
            try camera.lockForConfiguration()
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = point
                camera.focusMode = .autoFocus
            }
            camera.unlockForConfiguration()
        } catch {
            print("Failed to set focus point: \(error)")
        }
    }

    /// setexposure
    func setExposurePoint(_ point: CGPoint) {
        guard let camera = currentCamera else { return }
        do {
            try camera.lockForConfiguration()
            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = point
                camera.exposureMode = .autoExpose
            }
            camera.unlockForConfiguration()
        } catch {
            print("Failed to set exposure point: \(error)")
        }
    }

    // MARK: - white balancecompatibilitymethod(WhiteBalanceManager)

    /// autowhite balance(used forpreviewstagerestore AWB)
    func setAutoWhiteBalanceContinuous() {
        whiteBalanceManager.enableAutoMode()
    }

    /// autowhite balancemode
    func enableAutoWhiteBalance() {
        whiteBalanceManager.enableAutoMode()
    }

    /// getwhite balancetemperaturerange
    func getWhiteBalanceRange() -> (min: Float, max: Float) {
        whiteBalanceManager.getTemperatureRange()
    }

    /// setwhite balance(compatibilitymethod)
    func setWhiteBalance(temperature: Float, tint: Float = 0) {
        whiteBalanceManager.setWhiteBalance(temperature: temperature, tint: tint)
    }

    /// getcurrentwhite balanceset(compatibilitymethod)
    func getCurrentWhiteBalance() -> (temperature: Float, tint: Float, mode: AVCaptureDevice.WhiteBalanceMode) {
        whiteBalanceManager.getCurrentWhiteBalance()
    }

    /// setpreviewmodewhite balance(compatibilitymethod)
    func setPreviewWhiteBalance(temperature: Float, tint: Float = 0, mode: AVCaptureDevice.WhiteBalanceMode = .autoWhiteBalance) {
        whiteBalanceManager.setPreviewWhiteBalance(temperature: temperature, tint: tint, mode: mode)
    }

    /// white balancerelatedproperties(compatibility)
    var isManualWhiteBalanceMode: Bool {
        whiteBalanceManager.isManualMode
    }

    var manualWhiteBalance: Float {
        get { whiteBalanceManager.manualTemperature }
        set { whiteBalanceManager.manualTemperature = newValue }
    }

    /// getcurrentcameradevicecapability
    func getCurrentCameraCapabilities() -> (minISO: Float, maxISO: Float, minExposure: CMTime, maxExposure: CMTime, minZoom: Double, maxZoom: Double)? {
        guard let camera = currentCamera else { return nil }

        return (
            minISO: camera.activeFormat.minISO,
            maxISO: camera.activeFormat.maxISO,
            minExposure: camera.activeFormat.minExposureDuration,
            maxExposure: camera.activeFormat.maxExposureDuration,
            minZoom: Double(camera.minAvailableVideoZoomFactor),
            maxZoom: Double(camera.maxAvailableVideoZoomFactor)
        )
    }

    // MARK: - devicecapabilitycheckmethod

    /// checkcurrentdevicewhethersupport Raw formatcapture(need to photoOutput)
    func isRawCaptureSupported(photoOutput: AVCapturePhotoOutput?) -> Bool {
        guard let photoOutput else { return false }
        return !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
    }

    /// checkcurrentdevicewhethersupport Apple ProRaw format(need to photoOutput)
    func isProRawCaptureSupported(photoOutput: AVCapturePhotoOutput?) -> Bool {
        if #available(iOS 14.3, *) {
            guard let photoOutput else { return false }
            return photoOutput.isAppleProRAWSupported
        }
        return false
    }

    /// getavailable Raw format(need to photoOutput)
    func getAvailableRawPixelFormatTypes(photoOutput: AVCapturePhotoOutput?) -> [OSType] {
        guard let photoOutput else { return [] }
        return photoOutput.availableRawPhotoPixelFormatTypes
    }

    /// checkcapturequalitywhethersupport(need to photoOutput)
    func isCaptureQualitySupported(_ quality: CameraSettingsState.CaptureQuality, photoOutput: AVCapturePhotoOutput?) -> Bool {
        switch quality {
        case .standard:
            return true
        case .proRaw:
            return isProRawCaptureSupported(photoOutput: photoOutput)
        }
    }

    /// getsupportcapturequality(need to photoOutput)
    func getSupportedCaptureQualities(photoOutput: AVCapturePhotoOutput?) -> [CameraSettingsState.CaptureQuality] {
        CameraSettingsState.CaptureQuality.allCases.filter { isCaptureQualitySupported($0, photoOutput: photoOutput) }
    }

    // MARK: - videocapability

    /// checkvideowhethersupport
    func isVideoResolutionSupported(_ resolution: CameraSettingsState.VideoResolution) -> Bool {
        guard let device = currentCamera else { return false }

        let targetDimensions = resolution.dimensions
        return device.formats.contains { (format: AVCaptureDevice.Format) -> Bool in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let isResolutionSupported = Int(dimensions.width) >= Int(targetDimensions.width) &&
                Int(dimensions.height) >= Int(targetDimensions.height)

            if !isResolutionSupported {
                return false
            }

            // checkwhethersupport 30fps
            let ranges = format.videoSupportedFrameRateRanges
            return ranges.contains { range in
                range.minFrameRate <= 30.0 && range.maxFrameRate >= 30.0
            }
        }
    }

    /// checkvideowhethersupport
    func isVideoFrameRateSupported(_ frameRate: CameraSettingsState.VideoFrameRate) -> Bool {
        guard let device = currentCamera else { return false }

        let targetFrameRate = frameRate.value
        return device.formats.contains { (format: AVCaptureDevice.Format) -> Bool in
            let ranges = format.videoSupportedFrameRateRanges
            return ranges.contains { range in
                range.minFrameRate <= targetFrameRate && range.maxFrameRate >= targetFrameRate
            }
        }
    }

    /// getsupportvideo(,)
    func getSupportedVideoResolutions() -> [CameraSettingsState.VideoResolution] {
        let allResolutions = CameraSettingsState.VideoResolution.allCases
        let supportedResolutions = allResolutions.filter { isVideoResolutionSupported($0) }

        // , letquality
        return supportedResolutions.sorted { $0.pixelCount > $1.pixelCount }
    }

    /// getsupportvideo(,)
    func getSupportedVideoFrameRates() -> [CameraSettingsState.VideoFrameRate] {
        let allFrameRates = CameraSettingsState.VideoFrameRate.allCases
        let supportedFrameRates = allFrameRates.filter { isVideoFrameRateSupported($0) }

        // , let
        return supportedFrameRates.sorted { $0.value > $1.value }
    }

    /// getdevicesupportvideo
    func getMaxSupportedVideoResolution() -> CameraSettingsState.VideoResolution {
        let supportedResolutions = getSupportedVideoResolutions()
        return supportedResolutions.first ?? .hd1080 // default 1080p
    }

    /// getdevicesupportvideo
    func getMaxSupportedVideoFrameRate() -> CameraSettingsState.VideoFrameRate {
        let supportedFrameRates = getSupportedVideoFrameRates()
        return supportedFrameRates.first ?? .fps30 // default 30fps
    }

    /// checkvideosaveformatwhethersupport
    func isVideoSaveFormatSupported(_: CameraSettingsState.VideoSaveFormat) -> Bool {
        // MOV and MP4 iOS support
        true
    }

    /// getsupportvideosaveformat
    func getSupportedVideoSaveFormats() -> [CameraSettingsState.VideoSaveFormat] {
        CameraSettingsState.VideoSaveFormat.allCases.filter { isVideoSaveFormatSupported($0) }
    }
}

// MARK: - AVCaptureDevice.Format Extension

extension AVCaptureDevice.Format {
    /// checkformatwhethersupport
    func isSupported(withFrameRate frameRate: CMTimeScale) -> Bool {
        videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= Double(frameRate) && range.maxFrameRate >= Double(frameRate)
        }
    }

    /// checkformatwhethersupport
    func isSupported(withFrameRate frameRate: CMTimeScale, dimensions: CMVideoDimensions) -> Bool {
        let formatDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let isResolutionSupported = Int(formatDimensions.width) >= Int(dimensions.width) &&
            Int(formatDimensions.height) >= Int(dimensions.height)

        guard isResolutionSupported else { return false }

        return videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= Double(frameRate) && range.maxFrameRate >= Double(frameRate)
        }
    }

    /// getformatsupport(not minimum)
    static func maxFrameRate(forFormat format: AVCaptureDevice.Format, minFrameRate: CMTimeScale) -> CMTimeScale {
        CMTimeScale(format.videoSupportedFrameRateRanges
            .compactMap { range in range.maxFrameRate >= Double(minFrameRate) ? range.maxFrameRate : nil }
            .max() ?? Double(minFrameRate))
    }
}

// MARK: - DeviceType Mapping Helper

extension AVCaptureDevice {
    /// Map AVCaptureDevice type and position to CameraDeviceType
    var cameraDeviceType: CameraDeviceType {
        switch (deviceType, position) {
        case (.builtInUltraWideCamera, .back): return .ultraWide
        case (.builtInWideAngleCamera, .back): return .backWide
        case (.builtInWideAngleCamera, .front): return .frontWide
        case (.builtInTelephotoCamera, .back): return .telephoto
        default: return .backWide
        }
    }
}
