import AVFoundation
import Combine
import Foundation
import UIKit

/// cameracapture - capturelogic
@MainActor
final class CameraCaptureService: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = CameraCaptureService()

    // MARK: - Dependencies

    private var settingsState: CameraSettingsState { CameraSettingsState.shared }
    private var photoProcessor: PhotoProcessor { PhotoProcessor.shared }
    private var livePhotoProcessor: LivePhotoProcessor { LivePhotoProcessor.shared }
    private var photoCaptureSettings: PhotoCaptureSettings { PhotoCaptureSettings.shared }
    private var metadataBuilder: MetadataBuilder { MetadataBuilder.shared }

    // MARK: - State Machine

    let captureStateMachine = CaptureStateMachine()

    // MARK: - Publishers

    private let errorSubject = PassthroughSubject<String, Never>()
    var errorPublisher: AnyPublisher<String, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    // MARK: - Processors

    // usevideorecording
    private let recorderLock = NSLock()
    private nonisolated(unsafe) var _movieRecorder: MovieRecorder?
    private nonisolated(unsafe) var _originalMovieRecorder: MovieRecorder?

    private nonisolated var movieRecorder: MovieRecorder? {
        get { recorderLock.withLock { _movieRecorder } }
        set { recorderLock.withLock { _movieRecorder = newValue } }
    }

    private nonisolated var originalMovieRecorder: MovieRecorder? {
        get { recorderLock.withLock { _originalMovieRecorder } }
        set { recorderLock.withLock { _originalMovieRecorder = newValue } }
    }

    // MARK: - State Management

    /// captureresult, used for saving state
    private var pendingCaptureResult: CaptureResult?

    /// state
    private var stateTimeoutTask: Task<Void, Never>?

    /// capturing state(processing/saving)
    private var capturingTimeoutTask: Task<Void, Never>?

    /// videorecordingstate
    private var pendingFilteredVideoURL: URL?
    private var pendingOriginalVideoURL: URL?

    // MARK: - Dependencies for Processors

    private var sessionManager: CameraSessionManager { .shared }
    private var orientationManager: OrientationManager { .shared }
    private var automationManager: CameraAutomationManager { .shared }
    private var audioManager: AudioManager { .shared }

    // MARK: - Constants

    private let minStorageSpace: Int64 = 100 * 1024 * 1024 // 100MB
    private let stateTimeoutSeconds: UInt64 = 40
    private let capturingTimeoutSeconds: UInt64 = 5 // photocapture(), videorecordingnot

    // MARK: - Haptic Feedback

    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private let errorFeedback = UINotificationFeedbackGenerator()

    // MARK: - Initialization

    override private init() {
        super.init()

        setupStateObserver()
        setupNotificationObservers()
        configureProcessors()
    }

    private func configureProcessors() {
        // configurephotoprocessor
        photoProcessor.delegate = self

        // initializationvideorecording(filter)
        movieRecorder = MovieRecorder(
            orientationManager: orientationManager,
            sessionManager: sessionManager
        )
        movieRecorder?.delegate = self

        // initializationoriginalvideorecording(onlysaveuse)
        originalMovieRecorder = MovieRecorder(
            orientationManager: orientationManager,
            sessionManager: sessionManager
        )
        originalMovieRecorder?.delegate = self
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .cameraUserAction,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let action = notification.userInfo?[CameraNotificationKeys.action] as? CameraViewState.UserAction else { return }
            self?.handleUserAction(action)
        }

        NotificationCenter.default.addObserver(
            forName: .cameraSaveFinished,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let success = notification.userInfo?[CameraNotificationKeys.saveSuccess] as? Bool ?? false
            self?.handleSaveFinished(success: success)
        }
    }

    private func handleSaveFinished(success: Bool) {
        print("📡 [CaptureService] Received save finished notification. Success: \(success)")
        if success {
            captureStateMachine.completeSaving()
        } else {
            captureStateMachine.reportError()
        }
    }

    private func handleUserAction(_ action: CameraViewState.UserAction) {
        print("📡 [CaptureService] Received broadcast action: \(action)")
        switch action {
        case .startCapture, .startTimerCapture:
            startCapture()
        case .stopRecording:
            endCapture()
        case .cancel:
            cancelCapture()
        case .reset:
            reset()
        case .requestAIInspiration:
            break
        }
    }

    private func setupStateObserver() {
        captureStateMachine.addStateChangeObserver { [weak self] old, new in
            Task { @MainActor [weak self] in
                await self?.handleCaptureStateChange(old, new)
            }
        }
    }

    deinit {
        print("🗑️ [CaptureService] deinit")
        stateTimeoutTask?.cancel()
    }

    // MARK: - Private Helpers

    /// errorandresetstate
    private func reportError(_ error: Error) {
        errorSubject.send(error.localizedDescription)
        captureStateMachine.forceReset()
    }

    /// createrecordingconfigure
    private func createRecordingConfig(isOriginal: Bool) -> RecordingConfig? {
        RecordingConfig(
            videoFrameRate: settingsState.videoFrameRate.value,
            videoResolution: settingsState.videoResolution,
            videoSaveFormat: settingsState.videoSaveFormat,
            fileNamingTemplate: settingsState.effectiveFileNamingTemplate,
            fileNamingPrefix: settingsState.fileNamingPrefix,
            isOriginal: isOriginal
        )
    }

    /// clean upvideorecordingstate
    private func clearVideoRecordingState() {
        pendingFilteredVideoURL = nil
        pendingOriginalVideoURL = nil
    }

    // MARK: - Capture Control

    /// startcapture
    func startCapture() {
        // : ifcurrentcountdownstate, countdownend, preparestage
        if captureStateMachine.currentState == .countingDown {
            captureStateMachine.startActualCapture()
            return
        }

        // checkstate(error staterestore)
        guard captureStateMachine.currentState.canStartCapture else { return }

        lightFeedback.impactOccurred()

        // setcapturecontextandstartcapture
        captureStateMachine.setContext(
            mode: settingsState.currentCaptureMode,
            isTimerEnabled: settingsState.timerCaptureEnabled,
            isAutomationEnabled: settingsState.automationEnabled
        )

        let result = captureStateMachine.startCapture()
        if !result.success {
            captureStateMachine.reportError()
        }
    }

    /// startvideorecording
    @discardableResult
    @MainActor
    func startVideoRecording() async -> Bool {
        guard let videoRecorder = movieRecorder,
              let config = createRecordingConfig(isOriginal: false)
        else {
            return false
        }

        let success = videoRecorder.startRecording(with: config)
        if success {
            AnalyticsManager.shared.log(.startVideoRecording(filter: FilterManager.shared.selectedFilter.id))
        }

        // ifsave, originalrecording
        if success, settingsState.saveOriginalEnabled,
           let originalRecorder = originalMovieRecorder,
           let originalConfig = createRecordingConfig(isOriginal: true)
        {
            print("🎬 [CaptureService] 启动原片录制器 (isOriginal=\(originalConfig.isOriginal))")
            originalRecorder.startRecording(with: originalConfig)
        }

        return success
    }

    /// stopvideorecording
    func stopVideoRecording() {
        movieRecorder?.stopRecording()
        AnalyticsManager.shared.log(.endVideoRecording(duration: nil))
        captureStateMachine.completeCapture()

        // iforiginalrecordingin progress, stop
        if originalMovieRecorder?.isRecording == true {
            originalMovieRecorder?.stopRecording()
        }
    }

    /// getprocessor(used forCameraPreviewView)
    func getPhotoProcessor() -> PhotoProcessor? {
        photoProcessor
    }

    func getVideoRecorder() -> MovieRecorder? {
        movieRecorder
    }

    func getOriginalVideoRecorder() -> MovieRecorder? {
        originalMovieRecorder
    }

    func getLivePhotoProcessor() -> LivePhotoProcessor? {
        livePhotoProcessor
    }

    /// audiodata
    nonisolated func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        recorderLock.lock()
        let recorder = _movieRecorder
        let original = _originalMovieRecorder
        recorderLock.unlock()

        recorder?.appendAudioSampleBuffer(sampleBuffer)
        original?.appendAudioSampleBuffer(sampleBuffer)
    }

    /// videodata
    nonisolated func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        recorderLock.lock()
        let recorder = _movieRecorder
        let original = _originalMovieRecorder
        recorderLock.unlock()

        recorder?.appendVideoSampleBuffer(sampleBuffer)
        original?.appendVideoSampleBuffer(sampleBuffer)
    }

    /// updatephotoprocessor
    func updatePhotoProcessorAspectRatio(_ aspectRatio: Double) {
        photoProcessor.updateAspectRatio(aspectRatio)
    }

    /// updateflashmode
    func updateFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        photoCaptureSettings.updateFlashMode(mode)
    }

    func endCapture() {
        let captureMode = captureStateMachine.context?.mode ?? settingsState.currentCaptureMode

        switch captureMode {
        case .photo, .livePhoto:
            if captureStateMachine.currentState.isWaiting {
                cancelCapture()
            }
        case .movie:
            if captureStateMachine.currentState.isCapturing {
                lightFeedback.impactOccurred()
                stopVideoRecording()
            }
        }
    }

    /// currentcaptureoperation
    func cancelCapture() {
        lightFeedback.impactOccurred()
        captureStateMachine.cancel()
    }

    /// trigger(button, volume, take a photo)logic
    func triggerShutterAction() {
        let state = captureStateMachine.currentState

        if state.isWaiting || (settingsState.currentCaptureMode == .movie && state.isCapturing) {
            // ifin progresswait(countdown/prepare)in progressrecordingvideo, stop/
            print("📸 [CaptureService] 快门触发：停止或取消当前操作 (state: \(state))")
            endCapture()
        } else if state.canStartCapture {
            // otherwise, ifidlestate, startcapture
            print("📸 [CaptureService] 快门触发：开始拍摄流程")
            startCapture()
        }
    }

    func reset() {
        captureStateMachine.forceReset()
    }

    /// capture(state)
    func executeCapture() async {
        let captureMode = settingsState.currentCaptureMode

        switch captureMode {
        case .photo, .livePhoto:
            await executePhotoCapture(isLivePhoto: captureMode == .livePhoto)
        case .movie:
            await executeVideoCapture()
        }
    }

    // MARK: - Capture State Change Handler

    /// Get current memory usage (MB)
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0.0
    }

    /// capturestate
    func handleCaptureStateChange(_ old: CaptureState, _ new: CaptureState) async {
        // memory
        let memory = getMemoryUsage()
        print("📊 [Memory] State: \(old) → \(new), Memory: \(String(format: "%.1f", memory))MB")

        stateTimeoutTask?.cancel()
        capturingTimeoutTask?.cancel()

        // capturing stateset(onlyphotomode, videorecordingnot)
        if new == .capturing, captureStateMachine.context?.isVideoMode == false {
            capturingTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: (self?.capturingTimeoutSeconds ?? 5) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.captureStateMachine.currentState == .capturing
                    else { return }
                    print("⚠️ [CaptureService] Capturing timeout - forcing error state")
                    self.reportError(CaptureError.captureTimeout)
                }
            }
        }

        // processing/saving set
        if new == .processing || new == .saving {
            stateTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: (self?.stateTimeoutSeconds ?? 20) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.captureStateMachine.currentState == .processing ||
                          self.captureStateMachine.currentState == .saving
                    else { return }
                    self.reportError(CaptureError.saveTimeout)
                }
            }
        }

        // statenotify
        NotificationCenter.default.post(
            name: .cameraCaptureStateChanged,
            object: nil,
            userInfo: [CameraNotificationKeys.captureState: new]
        )

        // stateoperation
        switch new {
        case .preparing:
            if captureStateMachine.context?.isAutomationEnabled == true {
                await automationManager.triggerBeforeCapture()
            }
            captureStateMachine.startActualCapture()

        case .capturing:
            await executeCapture()

        case .processing:
            break // waitcomplete

        case .saving:
            if let result = pendingCaptureResult {
                // triggersave, not then View
                Task {
                    await CameraSaveService.shared.handleCaptureResult(result)
                }
                pendingCaptureResult = nil
            } else {
                captureStateMachine.completeSaving()
            }

        case .completed:
            if captureStateMachine.context?.isAutomationEnabled == true {
                await automationManager.triggerAfterCapture()
            }
            // ensureclean upreference
            pendingCaptureResult = nil
            captureStateMachine.reset()

            // memory
            let completedMemory = getMemoryUsage()
            print("📊 [Memory] Completed state cleanup - Memory: \(String(format: "%.1f", completedMemory))MB")

        case .idle:
            pendingCaptureResult = nil
            clearVideoRecordingState()

        case .error:
            pendingCaptureResult = nil
            clearVideoRecordingState()

        case .countingDown:
            break
        }
    }

    // MARK: - Private Methods

    private func executePhotoCapture(isLivePhoto: Bool) async {
        // configuretake a photoset
        photoCaptureSettings.updateFlashMode(settingsState.flashMode)
        await photoCaptureSettings.updateLivePhoto(isLivePhoto)

        let quality = settingsState.captureQuality
        let format = settingsState.imageFileFormat

        let (photoSettings, _) = photoCaptureSettings.buildPhotoSettings(quality: quality, format: format)

        // Live Photomodeinitialization
        if isLivePhoto {
            let uniqueID = Int(photoSettings.uniqueID)
            let orientation = orientationManager.currentDeviceOrientation
            Task { await livePhotoProcessor.beginCapture(uniqueID: uniqueID, orientation: orientation) }
        }

        photoProcessor.setPhotoCaptureCompletion { _ in }

        guard let photoOutput = sessionManager.getStillImageOutput() else {
            reportError(CaptureError.initializationFailed)
            return
        }

        photoOutput.capturePhoto(with: photoSettings, delegate: self)

        AnalyticsManager.shared.log(.capturePhoto(
            mode: isLivePhoto ? "livePhoto" : "photo",
            filter: FilterManager.shared.selectedFilter.id
        ))
    }

    private func executeVideoCapture() async {
        guard hasEnoughStorageSpace() else {
            reportError(CaptureError.insufficientStorage)
            return
        }

        let success = await startVideoRecording()
        if success {
            lightFeedback.impactOccurred()
        } else {
            reportError(CaptureError.videoRecordingFailed)
            errorFeedback.notificationOccurred(.error)
        }
    }

    private func hasEnoughStorageSpace() -> Bool {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return (values.volumeAvailableCapacityForImportantUsage ?? 0) > minStorageSpace
        } catch {
            print("❌ [CaptureService] Failed to check storage space: \(error)")
            return true // defaultrecording
        }
    }
}

// MARK: - PhotoProcessorDelegate

@MainActor
extension CameraCaptureService: PhotoProcessorDelegate {
    func photoProcessor(_: PhotoProcessor, didFinishProcessing result: CaptureResult) {
        if let uniqueID = result.metadata?["uniqueID"] as? Int {
            // Live Photo mode
            Task {
                await livePhotoProcessor.saveImageData(
                    uniqueID: uniqueID,
                    filteredImage: result.filteredImage,
                    originalImage: result.originalImage,
                    originalImageData: result.originalImageData,
                    metadata: result.metadata
                )
            }
        } else {
            // regular photomode
            pendingCaptureResult = result
            captureStateMachine.startSaving()
        }
    }

    func photoProcessor(_: PhotoProcessor, didFailWithError error: Error?) {
        if let error {
            reportError(error)
        } else {
            reportError(CaptureError.processingFailed)
        }
    }
}

// MARK: - VideoRecorderDelegate

@MainActor
extension CameraCaptureService: MovieRecorderDelegate {
    func movieRecorder(_ recorder: MovieRecorder, didStartRecordingTo _: URL) {
        let isOriginal = recorder === originalMovieRecorder
        print("🎬 [CaptureService] \(isOriginal ? "原始" : "带滤镜")视频录制开始")
    }

    func movieRecorder(_ recorder: MovieRecorder, didFinishRecordingTo url: URL, error: Error?) {
        let isOriginal = recorder === originalMovieRecorder

        if let error {
            print("❌ [CaptureService] \(isOriginal ? "原始" : "带滤镜")视频录制失败: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            if !isOriginal {
                reportError(error)
            }
            return
        }

        print("✅ [CaptureService] \(isOriginal ? "原始" : "带滤镜")视频录制完成: \(url.lastPathComponent)")

        // save URL
        if isOriginal {
            pendingOriginalVideoURL = url
        } else {
            pendingFilteredVideoURL = url
        }

        // checkwhetherpreparecomplete: filtervideo
        guard pendingFilteredVideoURL != nil else {
            print("⏳ [CaptureService] 等待带滤镜视频录制完成...")
            return
        }

        // ifneed to save, checkwhether
        let needsOriginal = settingsState.saveOriginalEnabled
        if needsOriginal, pendingOriginalVideoURL == nil {
            if originalMovieRecorder?.isRecording == true {
                print("⏳ [CaptureService] 等待原始视频录制完成...")
                return
            } else {
                print("⚠️ [CaptureService] 需要保存原片但原始视频未就绪，将仅保存带滤镜视频")
            }
        }

        // generateresult
        let metadata = metadataBuilder.buildVideoMetadata(camera: CameraDeviceManager.shared.getCurrentCamera())
        let captureResult = CaptureResult(
            originalImage: UIImage(),
            filteredImage: UIImage(),
            metadata: metadata,
            livePhotoURL: nil,
            originalImageData: nil,
            videoURL: pendingFilteredVideoURL,
            originalVideoURL: pendingOriginalVideoURL
        )

        print("💾 [CaptureService] 视频结果生成 - 带滤镜: \(pendingFilteredVideoURL?.lastPathComponent ?? "nil"), 原始: \(pendingOriginalVideoURL?.lastPathComponent ?? "nil")")

        // setresult, thentriggerstate
        pendingCaptureResult = captureResult
        clearVideoRecordingState()
        captureStateMachine.startSaving()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

@MainActor
extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        captureStateMachine.completeCapture()
        photoProcessor.setPhotoCaptureCompletion { _ in }
        photoProcessor.photoOutput(output, didFinishProcessingPhoto: photo, error: error)
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration _: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            Task { await livePhotoProcessor.cancelCapture(uniqueID: Int(resolvedSettings.uniqueID)) }
            print("❌ [CaptureService] Live Photo 视频处理失败: \(error.localizedDescription)")
            return
        }

        Task(priority: .userInitiated) {
            let filter = FilterManager.shared.selectedFilter
            let isMuted = audioManager.isMuted

            await livePhotoProcessor.saveVideoURL(
                uniqueID: Int(resolvedSettings.uniqueID),
                videoURL: outputFileURL,
                filter: filter,
                photoDisplayTime: photoDisplayTime,
                isMuted: isMuted
            )

            if let result = await livePhotoProcessor.finishCapture(uniqueID: Int(resolvedSettings.uniqueID)) {
                await MainActor.run {
                    self.pendingCaptureResult = result
                    captureStateMachine.startSaving()
                }
            }
        }
    }
}

// MARK: - Errors

/// captureerror
enum CaptureError: Error, LocalizedError {
    case initializationFailed
    case insufficientStorage
    case videoRecordingFailed
    case processingFailed
    case saveTimeout
    case captureTimeout
    case unknown(String?)

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "capture_error_init_failed".localized
        case .insufficientStorage:
            return "capture_error_insufficient_storage".localized
        case .videoRecordingFailed:
            return "capture_error_recording_failed".localized
        case .processingFailed:
            return "capture_error_processing_failed".localized
        case .saveTimeout:
            return "capture_error_save_timeout".localized
        case .captureTimeout:
            return "capture_error_capture_timeout".localized
        case let .unknown(message):
            return message ?? "capture_error_unknown".localized
        }
    }
}
