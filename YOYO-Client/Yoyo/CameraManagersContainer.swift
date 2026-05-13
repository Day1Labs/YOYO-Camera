import Combine
import SwiftUI

/// Container for camera managers, grouping related managers together for better performance
@MainActor
final class CameraManagersContainer: ObservableObject {
    // MARK: - Core Managers

    let deviceManager = CameraDeviceManager.shared
    let filterManager = FilterManager.shared
    let frameManager = FrameManager.shared
    let inspirationManager = InspirationManager.shared
    let volumeButtonManager = VolumeButtonManager.shared
    let orientationManager = OrientationManager.shared
    let locationManager = LocationManager.shared
    let aestheticsScoreManager = AestheticsScoreManager.shared
    let focusManager = FocusManager.shared
    let exposureManager = ExposureManager.shared
    let automationManager = CameraAutomationManager.shared
    let audioManager = AudioManager.shared
    private var cameraControlManager: Any? {
        if #available(iOS 18.0, *) {
            return CameraControlManager.shared
        }
        return nil
    }

    // MARK: - Services

    let captureService = CameraCaptureService.shared
    let previewRenderController = PreviewRenderController.shared
    let previewFrameProvider = PreviewFrameProvider.shared
    let sampleBufferController = SampleBufferController.shared

    // MARK: - Session Managers

    let sessionManager = CameraSessionManager.shared

    // MARK: - State Managers

    let settingsState = CameraSettingsState.shared
    @Published var viewState = CameraViewState.shared

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupStatePropagation()
    }

    /// Sets up state propagation so changes in `viewState` and `settingsState` notify the container
    private func setupStatePropagation() {
        forwardChanges(from: viewState)
        forwardChanges(from: captureService)
        forwardChanges(from: settingsState)
        forwardChanges(from: automationManager)

        captureService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                print("❌ [CameraManagersContainer] Received capture error: \(errorMessage)")
                self?.viewState.showError(errorMessage)
            }
            .store(in: &cancellables)

        settingsState.$currentCaptureMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] captureMode in
                self?.handleCaptureModeChange(captureMode)
            }
            .store(in: &cancellables)

        setupNotifications()
    }

    /// Updates the video configuration
    private func updateVideoConfiguration() {
        let resolution = settingsState.videoResolution.dimensions
        let frameRate = settingsState.videoFrameRate.value
        let currentMode = settingsState.currentCaptureMode
        print("🔄 [CameraManagersContainer] 更新视频配置: \(resolution.width)x\(resolution.height) @ \(frameRate)fps, 当前模式: \(currentMode.rawValue)")
        sessionManager.updateVideoConfiguration(videoResolution: resolution, videoFrameRate: frameRate)
    }

    private func forwardChanges(from observable: some ObservableObject) {
        observable.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func observeNotification(_ name: Notification.Name, action: @escaping (CameraManagersContainer) -> Void) {
        NotificationCenter.default.publisher(for: name)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                action(self)
            }
            .store(in: &cancellables)
    }

    private func setupNotifications() {
        observeNotification(.videoResolutionDidChange) { container in
            print("📡 [CameraManagersContainer] 收到 videoResolutionDidChange 通知")
            container.updateVideoConfiguration()
        }

        observeNotification(.videoFrameRateDidChange) { container in
            print("📡 [CameraManagersContainer] 收到 videoFrameRateDidChange 通知")
            container.updateVideoConfiguration()
        }

        observeNotification(.videoStabilizationDidChange) { container in
            container.sessionManager.updateVideoStabilization(enabled: container.settingsState.stabilizationEnabled)
        }

        // Observe completion of video format configuration and restore torch state
        // Note: restoration must happen after format configuration because changing `activeFormat` resets the torch
        observeNotification(.videoFormatConfigurationDidComplete) { container in
            container.restoreTorchStateIfNeeded()
            container.restoreZoomState()
        }

        // Observe session start completion and restore torch state when the app returns from background
        observeNotification(.cameraSessionDidStart) { container in
            container.restoreTorchStateIfNeeded()
        }

        // Observe session switch completion and restore torch state when switching cameras
        observeNotification(.cameraSessionDidSwitch) { container in
            container.restoreTorchStateIfNeeded()
        }
    }

    private func handleCaptureModeChange(_ captureMode: CameraCaptureMode) {
        print("🔄 [CameraManagersContainer] 拍摄模式变化: \(captureMode.rawValue)")

        // 1. Before switching modes, stop the previous capture if capture or recording is in progress
        captureService.endCapture()

        // 2 & 3. Perform the actual session switch and apply video settings once when entering video mode to avoid repeated preview refreshes
        if captureMode == .movie {
            let resolution = settingsState.videoResolution.dimensions
            let frameRate = settingsState.videoFrameRate.value
            let snapshot = CameraSessionManager.VideoSettingsSnapshot(
                resolution: resolution,
                frameRate: frameRate,
                stabilizationEnabled: settingsState.stabilizationEnabled
            )
            sessionManager.switchCaptureMode(to: captureMode, videoSettings: snapshot)
        } else {
            sessionManager.switchCaptureMode(to: captureMode, videoSettings: nil)
            // Keep the user's preference outside video mode, but do not apply it to the connection
            sessionManager.updateVideoStabilization(enabled: settingsState.stabilizationEnabled)
        }

        if captureMode != .movie {
            deviceManager.setTorch(enabled: false)
        }
    }

    /// Restores the torch state after a session switch completes, only in video mode
    private func restoreTorchStateIfNeeded() {
        guard settingsState.currentCaptureMode == .movie else { return }

        let shouldEnable = settingsState.torchEnabled

        // Debounce by checking the current device state to avoid redundant updates
        if let device = deviceManager.currentCamera {
            let isCurrentlyOn = device.torchMode == .on
            if isCurrentlyOn == shouldEnable {
                return
            }
        }

        print("🔦 [CameraManagersContainer] 恢复手电筒状态: \(shouldEnable)")
        deviceManager.setTorch(enabled: shouldEnable)
    }

    /// Restores the zoom state after a format switch completes
    private func restoreZoomState() {
        // Reapply zoom after a format switch because `activeFormat` resets `videoZoomFactor`
        let currentDeviceZoom = deviceManager.zoomManager.deviceZoomFactor
        // Force the update even if the value appears unchanged
        deviceManager.zoomManager.setZoomFactor(currentDeviceZoom)
    }

    // PermissionManager is no longer directly coupled with LocationManager, so no binding is needed here

    /// Starts monitoring services
    func startMonitoringServices() {
        orientationManager.startMonitoring()
        if settingsState.volumeButtonCaptureEnabled == true {
            volumeButtonManager.startMonitoring()
        }
        // Start location monitoring only when GPS saving is enabled
        if settingsState.saveGPSEnabled == true {
            locationManager.startMonitoring()
        }
    }

    /// Stop monitoring services
    func stopMonitoringServices() {
        orientationManager.stopMonitoring()
        volumeButtonManager.stopMonitoring()
        locationManager.stopMonitoring()
    }

    // MARK: - Lifecycle Management

    /// Stop the camera session when entering the background or presenting a full-screen cover
    func stopCamera() {
        // Before stopping the session, stop any ongoing capture or recording first
        captureService.endCapture()
        settingsState.isCaptureSessionActive = false
        sessionManager.stopSession()
        audioManager.reset()
        stopMonitoringServices()
    }

    /// Start the camera session when returning to the foreground or dismissing a full-screen cover
    func startCamera() {
        settingsState.isCaptureSessionActive = true
        sessionManager.startSession()
        startMonitoringServices()
    }

    /// Handle entering the background
    func handleEnterBackground() {
        stopCamera()
    }

    /// Handle returning to the foreground
    func handleEnterForeground() {
        // Reset the render controller state to avoid `isRendering` getting stuck
        previewRenderController.resetRenderingState()

        // Check whether there is a pending shortcut item
        if let shortcutMode = ShortcutItemHandler.shared.consumeCaptureMode() {
            settingsState.setCaptureMode(shortcutMode)
        }

        // Resume the camera if no full-screen cover is being shown
        if !viewState.showingPhotoGallery, !viewState.showingSettings {
            startCamera()
        }
    }
}
