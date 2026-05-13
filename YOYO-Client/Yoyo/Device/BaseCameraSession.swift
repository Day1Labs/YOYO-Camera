@preconcurrency import AVFoundation
import Combine

/// Session
class BaseCameraSession {
    let session = AVCaptureSession()
    private(set) var isConfigured = false
    private(set) var isRunning = false

    /// session operation queue
    let sessionQueue: DispatchQueue

    /// initialization - supportqueue
    init(sessionQueue: DispatchQueue) {
        // usequeue, otherwisecreatedefaultqueue
        self.sessionQueue = sessionQueue
        setupSession()
    }

    private func setupSession() {
        // session configure
        // autoconfigureaudiosession, manualmanagement()
        session.automaticallyConfiguresApplicationAudioSession = false
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    @objc private func handleSessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        // error, preview/
        let code = error.code.rawValue
        let userInfo = notification.userInfo ?? [:]
        print("❌ [\(type(of: self))] Session runtime error: \(error.localizedDescription) (code: \(code), domain: \(error._nsError.domain), userInfo: \(userInfo))")

        if error.code == .mediaServicesWereReset {
            sessionQueue.async { [weak self] in
                if self?.isRunning == true {
                    self?.session.startRunning()
                }
            }
        }
    }

    @objc private func handleSessionWasInterrupted(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int
        else { return }

        print("⚠️ [\(type(of: self))] Session interrupted, reason: \(reasonValue)")

        // 1: videoDeviceNotAvailableInBackground
        // 2: audioDeviceInUseByAnotherApp
        // 3: videoDeviceInUseByAnotherApp
        if reasonValue == 1 {
            // background
        } else if reasonValue == 2 || reasonValue == 3 {
            print("⚠️ [\(type(of: self))] Device in use by another app")
        }
    }

    @objc private func handleSessionInterruptionEnded(notification _: Notification) {
        print("✅ [\(type(of: self))] Session interruption ended")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isRunning, !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// implementconfiguremethod
    func configureSession() {
        fatalError("Subclass must implement configureSession()")
    }

    /// can method
    func setupOutputDelegates() {
        // defaultimplement, need to
    }

    func updateVideoConfiguration(videoResolution _: CGSize, videoFrameRate _: Double) {
        // defaultimplement, need to
    }

    /// Hook: called on `sessionQueue` right before configuring connection and starting running.
    /// Subclasses can override to apply settings that must be in place before the first frame.
    func willStartRunning(isFirstConfiguration _: Bool) {
        // defaultimplement, need to
    }

    /// implement: videodataoutput
    func getVideoDataOutput() -> AVCaptureVideoDataOutput? {
        fatalError("Subclass must implement getVideoDataOutput()")
    }

    /// configure video connection(implement, no need to)
    func configureVideoConnection() {
        guard let videoOutput = getVideoDataOutput(),
              let currentCamera = CameraDeviceManager.shared.getCurrentCamera()
        else { return }

        let videoConnectionManager = VideoConnectionManager.shared
        videoConnectionManager.setCurrentCamera(currentCamera)
        videoConnectionManager.setVideoDataOutput(videoOutput)
        videoConnectionManager.configureVideoConnection()
    }

    /// Session lifecycle management
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            let isFirstConfiguration = !self.isConfigured

            if !self.isConfigured {
                self.configureSession()
                self.isConfigured = true
            }

            guard !self.session.isRunning else { return }

            // Allow subclasses to apply settings before first frame.
            self.willStartRunning(isFirstConfiguration: isFirstConfiguration)

            // configure video connection, ensureorientation
            self.configureVideoConnection()
            self.session.startRunning()
            self.isRunning = true

            // configurecomplete, zoom
            if isFirstConfiguration {
                self.applyInitialZoom()
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cameraSessionDidStart, object: nil)
            }
        }
    }

    /// zoom(session)
    private func applyInitialZoom() {
        let deviceManager = CameraDeviceManager.shared
        guard let camera = deviceManager.getCurrentCamera(),
              camera.position == .back
        else { return }

        // setzoom 1.0x(wide camera)
        // use force: true (setZoomFactor)
        // need to main thread, becauseupdate @Published properties
        print("🔍 [\(type(of: self))] 应用初始缩放")
        DispatchQueue.main.async {
            deviceManager.zoomManager.resetZoom()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
                self.isRunning = false
                print("⏹️ [\(type(of: self))] Session stopped")
            }
        }
    }

    /// deviceswitchsupport
    func switchCamera(to device: AVCaptureDevice, targetZoom: Double? = nil, completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()

            // use inputConfigurator configurecamerainput, onlyremovevideoinput, audioinput
            // removeInput($0) audioinput, switchmodeno
            if CameraInputConfigurator.shared.configureCameraInput(for: self.session, device: device) {
                print("✅ [\(type(of: self))] Camera input switched to: \(device.deviceType.rawValue), position: \(device.position == .front ? "Front" : "Back")")
            }

            // ✅ ifzoom, device(commitConfiguration)
            // this waycan ensuredevicezoom,
            if let targetZoom {
                print("⚡ [\(type(of: self))] Applying immediate zoom: \(targetZoom)x")
                CameraDeviceManager.shared.zoomManager.applyZoomImmediately(to: device, deviceZoom: targetZoom)
            }

            // ✅ configure, let session completeconfigure, ensure Connection update
            self.session.commitConfiguration()

            // ensure connection thenconfigure
            self.configureVideoConnection()

            // configurecomplete, if session in progress, configure video connection
            if self.isRunning {
                DispatchQueue.main.async {
                    completion?()
                }
            } else {
                completion?()
            }
        }
    }

    /// configureaudioinput(used for)
    func reconfigureAudioInput() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            print("🎤 [\(type(of: self))] Reconfiguring audio input...")
            self.session.beginConfiguration()
            CameraInputConfigurator.shared.configureAudioInput(for: self.session)
            self.session.commitConfiguration()
        }
    }
}
