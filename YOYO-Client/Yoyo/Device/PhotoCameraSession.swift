@preconcurrency import AVFoundation

/// photo-specific session(.photo and.livePhoto mode)
final class PhotoCameraSession: BaseCameraSession {
    // output instances
    private(set) var photoOutput: AVCapturePhotoOutput?
    private(set) var videoDataOutput: AVCaptureVideoDataOutput?

    /// Live Photo state
    private var isLivePhotoEnabled: Bool = false

    /// Delegates
    private weak var videoSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?

    override func configureSession() {
        print("📸 [PhotoCameraSession] 开始配置照片 Session")

        session.beginConfiguration()

        // set preset
        session.sessionPreset = .photo

        // configurecamerainput
        if let device = CameraDeviceManager.shared.currentCamera {
            CameraInputConfigurator.shared.configureCameraInput(for: session, device: device)
        }

        // configurephotooutput
        photoOutput = CameraOutputConfigurator.shared.configurePhotoOutput(for: session, device: CameraDeviceManager.shared.currentCamera, enableLivePhoto: isLivePhotoEnabled)

        // configurevideodataoutput(used forpreview)
        videoDataOutput = CameraOutputConfigurator.shared.configureVideoDataOutput(for: session)

        session.commitConfiguration()

        // setoutput delegates
        setupOutputDelegates()

        print("✅ [PhotoCameraSession] 照片 Session 配置完成")
    }

    override func setupOutputDelegates() {
        if let videoOutput = videoDataOutput,
           let delegate = videoSampleBufferDelegate
        {
            videoOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(
                label: "com.day1-labs.yoyo.camera.photo.video",
                qos: .userInitiated
            ))
        }
    }

    /// set video delegate
    func setVideoDataOutputDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        videoSampleBufferDelegate = delegate
        if isConfigured {
            setupOutputDelegates()
        }
    }

    /// Session lifecycle management
    override func startSession() {
        // ensure Session Preset.photo
        // videomodeswitch, shareddeviceset activeFormat,
        // current Session preset can.inputPriority, Live Photo not available
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // onlyconfigurecheck preset, otherwise configureSession
            if self.isConfigured, self.session.sessionPreset != .photo {
                print("📸 [PhotoCameraSession] 检测到 preset 为 \(self.session.sessionPreset.rawValue)，重置为 .photo")
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.session.commitConfiguration()
            }
        }

        super.startSession()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.photoOutput?.isLivePhotoCaptureEnabled == true {
                AudioSessionManager.shared.activate()
            }
        }
    }

    override func stopSession() {
        super.stopSession()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.photoOutput?.isLivePhotoCaptureEnabled == true {
                AudioSessionManager.shared.deactivate()
            }
        }
    }

    /// Live Photo configuration
    func configureLivePhoto(_ enabled: Bool) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                // updatestate, ensure configureSession use
                self.isLivePhotoEnabled = enabled

                guard let photoOutput = self.photoOutput else {
                    print("📸 [PhotoCameraSession] LivePhoto 状态已更新为: \(enabled) (Session 未配置)")
                    continuation.resume()
                    return
                }

                self.session.beginConfiguration()

                // ensure preset, otherwise isLive PhotoCaptureSupported can false
                if self.session.sessionPreset != .photo {
                    print("📸 [PhotoCameraSession] configureLivePhoto: 重置 preset 为 .photo")
                    self.session.sessionPreset = .photo
                }

                if photoOutput.isLivePhotoCaptureSupported {
                    let wasEnabled = photoOutput.isLivePhotoCaptureEnabled
                    photoOutput.isLivePhotoCaptureEnabled = enabled
                    print("📸 [PhotoCameraSession] LivePhoto \(enabled ? "启用" : "禁用")")

                    if enabled {
                        // Live Photo need to audioinput
                        CameraInputConfigurator.shared.configureAudioInput(for: self.session)

                        // if session in progress, not yet, audio
                        if self.isRunning, !wasEnabled {
                            AudioSessionManager.shared.activate()
                        }
                    } else {
                        // Live Photo moderemoveaudioinput
                        CameraInputConfigurator.shared.removeAudioInput(from: self.session)

                        // if session in progress,, audio
                        if self.isRunning, wasEnabled {
                            AudioSessionManager.shared.deactivate()
                        }
                    }
                } else {
                    print("⚠️ [PhotoCameraSession] LivePhoto 不支持 (preset: \(self.session.sessionPreset.rawValue))")
                }

                self.session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    /// get output interfaces
    func getPhotoOutput() -> AVCapturePhotoOutput? {
        photoOutput
    }

    override func getVideoDataOutput() -> AVCaptureVideoDataOutput? {
        videoDataOutput
    }

    override func reconfigureAudioInput() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // only Live Photo configureaudioinput
            if self.isLivePhotoEnabled {
                print("🎤 [PhotoCameraSession] Reconfiguring audio input for Live Photo...")
                self.session.beginConfiguration()
                CameraInputConfigurator.shared.configureAudioInput(for: self.session)
                self.session.commitConfiguration()
            }
        }
    }
}
