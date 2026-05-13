@preconcurrency import AVFoundation
import Combine

/// refactored camera session manager - dual-session architecture
/// responsibilities: Session lifecycle managementconfigurecoordinate
final class CameraSessionManager {
    // MARK: - Properties

    static let shared = CameraSessionManager()

    /// photo-specific session
    private let photoSession: PhotoCameraSession

    /// video-specific session
    private let videoSession: VideoCameraSession

    /// currently active session
    private var activeSession: BaseCameraSession?

    /// AVCaptureSession (compatibilityinterface)
    var captureSession: AVCaptureSession? {
        activeSession?.session
    }

    /// session operation queue
    private let sessionQueue = DispatchQueue(
        label: "com.day1-labs.yoyo.camera.session",
        qos: .userInitiated
    )

    /// whether the video connection is ready
    private(set) var isVideoConnectionReady: Bool = false

    /// Video data output delegate
    private weak var videoSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

    /// Audio data output delegate
    private weak var audioSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate?

    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// whether the session has been initialized
    private var isSessionInitialized: Bool = false

    /// currently configured capture mode
    private var currentCaptureMode: CameraCaptureMode?

    struct VideoSettingsSnapshot: Equatable {
        let resolution: CGSize
        let frameRate: Double
        let stabilizationEnabled: Bool
    }

    // MARK: - Initialization

    private init() {
        // create sessionQueue and Session
        photoSession = PhotoCameraSession(sessionQueue: sessionQueue)
        videoSession = VideoCameraSession(sessionQueue: sessionQueue)

        // set Session dependencies
        setupSessionDependencies()

        setupObservers()
    }

    /// set Session dependencies
    private func setupSessionDependencies() {
        // set Session dependencies
        VideoConnectionManager.shared.onConfigurationReady = { [weak self] in
            self?.handleVideoConnectionReady()
        }
    }

    // MARK: - Session Lifecycle

    /// set up and initialize the camera session
    func setupSession(captureMode: CameraCaptureMode, videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?, audioDelegate: AVCaptureAudioDataOutputSampleBufferDelegate? = nil) {
        // 1. update delegate (keyfix: CameraPreviewView, update delegate)
        videoSampleBufferDelegate = videoDelegate
        audioSampleBufferDelegate = audioDelegate

        // set Session delegates
        photoSession.setVideoDataOutputDelegate(videoDelegate)
        videoSession.setVideoDataOutputDelegate(videoDelegate)
        videoSession.setAudioDataOutputDelegate(audioDelegate)

        // 2. ifinitialization, configure
        guard !isSessionInitialized else {
            print("⚠️ [CameraSessionManager] Session已初始化，仅更新Delegate")
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            // switch Session
            self.switchToSession(for: captureMode)

            // initialization
            self.isSessionInitialized = true
            self.currentCaptureMode = captureMode
        }
    }

    /// start the camera session
    func startSession() {
        guard let activeSession else {
            print("⚠️ [CameraSessionManager] 没有活跃Session，需要先调用setupSession")
            return
        }
        activeSession.startSession()

        // ✅ fix: ensureupdate the video connection configuration
        // backgroundrestorephoto librarysession
        // otherwise isVideoConnectionReady can false, videopreview
        //
        // AVCaptureSession.startRunning() async, connection can need to prepare
        // use: check, ifnot availableusedelay
        ensureVideoConnectionReady()
    }

    /// stop the camera session
    func stopSession() {
        activeSession?.stopSession()

        // ✅ reset video connection state, ensureconfigure
        sessionQueue.async { [weak self] in
            self?.isVideoConnectionReady = false
        }
    }

    // MARK: - Session Management

    /// switch to the session for the specified mode
    private func switchToSession(for mode: CameraCaptureMode) {
        let targetSession: BaseCameraSession = (mode == .movie) ? videoSession : photoSession

        // ✅ connectionconfigureupdatemode(whetherstabilization)
        VideoConnectionManager.shared.isVideoCaptureModeActive = (mode == .movie)

        // configure Live Photo
        if let photoSession = targetSession as? PhotoCameraSession {
            Task { await photoSession.configureLivePhoto(mode == .livePhoto) }
        }

        // if session,
        guard activeSession !== targetSession else { return }

        // whetherinitialization
        let isFirstInit = (activeSession == nil)

        // initialization
        if isFirstInit {
            targetSession.startSession()
            activeSession = targetSession

            // configure Camera Control (iOS 18+) - initialization
            if #available(iOS 18.0, *) {
                CameraControlManager.shared.setupControls(for: targetSession.session, sessionQueue: sessionQueue)
            }

            notifySessionSwitch(delay: 0.1)
            return
        }

        // switch
        isVideoConnectionReady = false

        // ✅ fix: only session configure, need to switchCamera
        // if session not yet configure, startSession -> configureSession autousecurrentcamera
        // not yet configure session switchCamera session not state, runtime error
        if targetSession.isConfigured, let currentCamera = CameraDeviceManager.shared.getCurrentCamera() {
            targetSession.switchCamera(to: currentCamera)
        }

        activeSession?.stopSession()
        targetSession.startSession()
        activeSession = targetSession

        // configure Camera Control (iOS 18+) - Session switchneed to configure(not AVCaptureSession)
        if #available(iOS 18.0, *) {
            CameraControlManager.shared.setupControls(for: targetSession.session, sessionQueue: sessionQueue)
        }

        updateVideoConnectionConfiguration()
        notifySessionSwitch(delay: 0.1)
    }

    private func notifySessionSwitch(delay: Double) {
        sessionQueue.asyncAfter(deadline: .now() + delay) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cameraSessionDidSwitch, object: nil)
            }
        }
    }

    /// configure Live Photo (public)
    func configureLivePhoto(_ enabled: Bool) async {
        if let photoSession = activeSession as? PhotoCameraSession {
            await photoSession.configureLivePhoto(enabled)
        }
    }

    /// update video configuration
    func updateVideoConfiguration(videoResolution: CGSize, videoFrameRate: Double) {
        sessionQueue.async { [weak self] in
            // no currentwhethervideo Session, configurevideo Session cache
            // this wayswitchvideomode, video Session useformat
            self?.videoSession.updateVideoConfiguration(videoResolution: videoResolution, videoFrameRate: videoFrameRate)
        }
    }

    /// switchcapturemode(videomodecan videoset)
    func switchCaptureMode(to captureMode: CameraCaptureMode, videoSettings: VideoSettingsSnapshot?) {
        guard currentCaptureMode != captureMode else {
            print("⚠️ [CameraSessionManager] 模式未变化(\(captureMode.rawValue))，跳过重复配置")
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if captureMode == .movie, let videoSettings {
                self.videoSession.cacheVideoConfiguration(
                    videoResolution: videoSettings.resolution,
                    videoFrameRate: videoSettings.frameRate
                )
                VideoConnectionManager.shared.stabilizationEnabled = videoSettings.stabilizationEnabled
            }

            self.switchToSession(for: captureMode)
            self.currentCaptureMode = captureMode
            VideoConnectionManager.shared.isVideoCaptureModeActive = (self.activeSession is VideoCameraSession)
        }
    }

    /// update video stabilization configuration
    func updateVideoStabilization(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // ✅ not videomode" false".
            // hereonlysave; whether isVideoCaptureModeActive.
            let was = VideoConnectionManager.shared.stabilizationEnabled
            VideoConnectionManager.shared.stabilizationEnabled = enabled

            let isVideoSession = self.activeSession is VideoCameraSession
            VideoConnectionManager.shared.isVideoCaptureModeActive = isVideoSession

            print("🎥 [CameraSessionManager] 更新防抖偏好: \(enabled) (VideoSession: \(isVideoSession))")

            if was != enabled, self.isVideoConnectionReady {
                VideoConnectionManager.shared.configureVideoConnection()
            }
        }
    }

    /// update the video connection configuration
    private func updateVideoConnectionConfiguration() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // getcurrent Session video data output
            let videoOutput = self.getVideoDataOutput()

            // update video connection manager
            if let currentCamera = CameraDeviceManager.shared.getCurrentCamera() {
                VideoConnectionManager.shared.setCurrentCamera(currentCamera)
            }

            // currentmode(whetherstabilization)
            VideoConnectionManager.shared.isVideoCaptureModeActive = (self.activeSession is VideoCameraSession)

            // configure video connection
            if let videoOutput,
               videoOutput.connection(with: .video) != nil
            {
                VideoConnectionManager.shared.setVideoDataOutput(videoOutput)
                VideoConnectionManager.shared.configureVideoConnection()
                self.isVideoConnectionReady = true
            } else {
                self.isVideoConnectionReady = false
            }
        }
    }

    // MARK: - Delegate Management

    /// set video data output delegate
    func setVideoDataOutputDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        videoSampleBufferDelegate = delegate

        // update Session delegate
        photoSession.setVideoDataOutputDelegate(delegate)
        videoSession.setVideoDataOutputDelegate(delegate)
    }

    /// set audio data output delegate
    func setAudioDataOutputDelegate(_ delegate: AVCaptureAudioDataOutputSampleBufferDelegate?) {
        audioSampleBufferDelegate = delegate

        // onlyvideo Session need to audio delegate
        videoSession.setAudioDataOutputDelegate(delegate)
    }

    // MARK: - Observer Setup

    /// set
    private func setupObservers() {
        // observedeviceorientation
        OrientationManager.shared.onOrientationChanged = { [weak self] _ in
            self?.updateVideoConnectionConfiguration()
        }

        // observedevice
        CameraDeviceManager.shared.$currentCameraDeviceType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateVideoConnectionConfiguration()
            }
            .store(in: &cancellables)

        // ✅ observe DeviceManager cameraswitch
        NotificationCenter.default.publisher(for: .deviceManagerRequestsCameraSwitch)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let camera = notification.object as? AVCaptureDevice else { return }
                let targetZoom = notification.userInfo?["targetZoom"] as? Double
                print("[SessionManager] 📡 收到相机切换请求: \(camera.deviceType.rawValue), targetZoom: \(String(describing: targetZoom))")
                self?.handleCameraSwitchRequest(camera, targetZoom: targetZoom)
            }
            .store(in: &cancellables)
    }

    /// cameraswitch(DeviceManager)
    private func handleCameraSwitchRequest(_ camera: AVCaptureDevice, targetZoom: Double? = nil) {
        print("📹 [SessionManager] 处理相机切换请求: \(camera.deviceType.rawValue)")

        sessionQueue.async { [weak self] in
            guard let self else { return }

            // video connection not yet
            self.isVideoConnectionReady = false

            // cameraswitch
            self.activeSession?.switchCamera(to: camera, targetZoom: targetZoom) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cameraSessionDidSwitch, object: nil)
                }
            }

            // update Controls (iOS 18+)
            if #available(iOS 18.0, *), let session = self.activeSession?.session {
                CameraControlManager.shared.setupControls(for: session, sessionQueue: self.sessionQueue, forceUpdate: true)
            }

            // update the video connection configuration
            self.updateVideoConnectionConfiguration()

            print("✅ [SessionManager] 相机切换完成")
        }
    }

    /// switchcapturemode
    func switchCaptureMode(to captureMode: CameraCaptureMode) {
        // configuremode
        guard currentCaptureMode != captureMode else {
            print("⚠️ [CameraSessionManager] 模式未变化(\(captureMode.rawValue))，跳过重复配置")
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            // switch Session
            self.switchToSession(for: captureMode)

            // updatecurrentconfiguremode
            self.currentCaptureMode = captureMode

            // updatecurrentmode(whetherstabilization)
            VideoConnectionManager.shared.isVideoCaptureModeActive = (self.activeSession is VideoCameraSession)
        }
    }

    /// session configure
    func performSessionConfiguration(_ configure: @escaping (AVCaptureSession) -> Void) {
        guard let session = captureSession else { return }

        sessionQueue.async {
            session.beginConfiguration()
            configure(session)
            session.commitConfiguration()
        }
    }

    /// get video data output(compatibilityinterface)
    func getVideoDataOutput() -> AVCaptureVideoDataOutput? {
        if let photoSession = activeSession as? PhotoCameraSession {
            return photoSession.getVideoDataOutput()
        } else if let videoSession = activeSession as? VideoCameraSession {
            return videoSession.getVideoDataOutput()
        }
        return nil
    }

    /// getcurrently active session(used for)
    func getActiveSession() -> BaseCameraSession? {
        activeSession
    }

    // MARK: - Camera Switching

    /// switchcamera(/)-
    func switchCameraPosition() {
        print("📹 [CameraSessionManager] 开始切换相机位置")
        sessionQueue.async { [weak self] in
            self?.isVideoConnectionReady = false
        }

        let deviceManager = CameraDeviceManager.shared

        // 1. deviceManager camera
        let currentPosition = deviceManager.getCurrentCamera()?.position ?? .back
        let targetPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back

        // 2. ✅ usesyncgetcamera
        guard let newCamera = deviceManager.switchToSync(position: targetPosition) else {
            print("⚠️ [CameraSessionManager] switchCameraPosition: 无法获取新相机")
            return
        }

        print("📹 [CameraSessionManager] 目标相机: \(newCamera.position == .front ? "前置" : "后置") (\(newCamera.deviceType.rawValue))")

        // 3. session cameraswitch
        activeSession?.switchCamera(to: newCamera) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cameraSessionDidSwitch, object: nil)
            }
        }

        print("✅ [CameraSessionManager] 相机切换完成")
    }

    // MARK: - Output Access Methods

    /// getcurrentphotooutput
    func getStillImageOutput() -> AVCapturePhotoOutput? {
        guard let photoSession = activeSession as? PhotoCameraSession else {
            return nil
        }
        return photoSession.getPhotoOutput()
    }

    // MARK: - Device Capability Methods (delegated from DeviceManager)

    /// checkcurrentdevicewhethersupport Raw formatcapture
    func isRawCaptureSupported() -> Bool {
        guard let photoOutput = getStillImageOutput() else { return false }
        return CameraDeviceManager.shared.isRawCaptureSupported(photoOutput: photoOutput)
    }

    /// checkcurrentdevicewhethersupport Apple ProRaw format
    func isProRawCaptureSupported() -> Bool {
        guard let photoOutput = getStillImageOutput() else { return false }
        return CameraDeviceManager.shared.isProRawCaptureSupported(photoOutput: photoOutput)
    }

    /// getavailable Raw format
    func getAvailableRawPixelFormatTypes() -> [OSType] {
        guard let photoOutput = getStillImageOutput() else { return [] }
        return CameraDeviceManager.shared.getAvailableRawPixelFormatTypes(photoOutput: photoOutput)
    }

    /// checkcapturequalitywhethersupport
    func isCaptureQualitySupported(_ quality: CameraSettingsState.CaptureQuality) -> Bool {
        let photoOutput = getStillImageOutput()
        return CameraDeviceManager.shared.isCaptureQualitySupported(quality, photoOutput: photoOutput)
    }

    /// getsupportcapturequality
    func getSupportedCaptureQualities() -> [CameraSettingsState.CaptureQuality] {
        let photoOutput = getStillImageOutput()
        return CameraDeviceManager.shared.getSupportedCaptureQualities(photoOutput: photoOutput)
    }

    /// configureaudioinput
    func reconfigureAudioInput() {
        activeSession?.reconfigureAudioInput()
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let cameraSessionDidChange = Notification.Name("cameraSessionDidChange")
    static let deviceManagerRequestsCameraSwitch = Notification.Name("deviceManagerRequestsCameraSwitch")
    static let cameraSessionWillSwitch = Notification.Name("cameraSessionWillSwitch")
    static let cameraSessionDidSwitch = Notification.Name("cameraSessionDidSwitch")
    static let cameraSessionDidStart = Notification.Name("cameraSessionDidStart")
    static let videoFormatConfigurationDidComplete = Notification.Name("videoFormatConfigurationDidComplete")
}

private extension CameraSessionManager {
    /// ensure video connection
    func ensureVideoConnectionReady() {
        let maxRetries = 3

        sessionQueue.async { [weak self] in
            guard let self else { return }

            for attempt in 1 ... maxRetries {
                if let output = self.getVideoDataOutput(),
                   output.connection(with: .video) != nil
                {
                    self.updateVideoConnectionConfiguration()
                    return
                }
                guard attempt < maxRetries else { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            self.isVideoConnectionReady = false
        }
    }

    func handleVideoConnectionReady() {
        sessionQueue.async { [weak self] in
            self?.isVideoConnectionReady = true
        }
    }
}
