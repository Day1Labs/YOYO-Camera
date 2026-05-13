@preconcurrency import AVFoundation

/// video-specific session(.movie mode)
final class VideoCameraSession: BaseCameraSession {
    // output instances
    private(set) var videoDataOutput: AVCaptureVideoDataOutput?
    private(set) var audioDataOutput: AVCaptureAudioDataOutput?

    // Delegates
    private weak var videoSampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    private weak var audioSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate?

    /// cached video configuration
    private var pendingResolution: CMVideoDimensions?
    private var pendingFrameRate: Int32?

    /// Session lifecycle management
    override func startSession() {
        // ✅ key: startRunning() AudioSession
        // Video modeaudioinput/output; if startRunning() switch.playAndRecord,
        // can trigger runtime error and sampleBuffer stopcallback(preview).
        // sessionQueue serialqueue, activate super.startSession() startRunning.
        sessionQueue.async {
            AudioSessionManager.shared.activate()
        }

        // ✅ fix: photomodevideomode, PhotoSession can shared device activeFormat.
        // video Session need to ensurevideoformatcurrentset, stabilization/capability.
        super.startSession()
    }

    override func willStartRunning(isFirstConfiguration _: Bool) {
        // ensurevideoformat(configure configureSession set, here)
        guard let device = CameraDeviceManager.shared.getCurrentCamera() else { return }

        let desiredResolution = pendingResolution ?? Self.defaultResolution
        let desiredFrameRate = pendingFrameRate ?? Self.defaultFrameRate

        // : current activeFormat
        let currentDimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let currentFPS = Int32(round(1.0 / max(0.000_001, CMTimeGetSeconds(device.activeVideoMinFrameDuration))))

        if currentDimensions.width == desiredResolution.width,
           currentDimensions.height == desiredResolution.height,
           currentFPS == desiredFrameRate
        {
            return
        }

        // startRunning format, ensure
        session.beginConfiguration()
        applyVideoFormat(to: device, resolution: desiredResolution, frameRate: desiredFrameRate)
        session.commitConfiguration()
    }

    override func stopSession() {
        super.stopSession()

        // audiosession
        sessionQueue.async {
            AudioSessionManager.shared.deactivate()
        }
    }

    /// default video configuration
    private static let defaultResolution = CMVideoDimensions(width: 1920, height: 1080)
    private static let defaultFrameRate: Int32 = 30

    override func configureSession() {
        print("🎥 [VideoCameraSession] 开始配置视频 Session, pendingResolution=\(String(describing: pendingResolution)), pendingFrameRate=\(String(describing: pendingFrameRate))")

        session.beginConfiguration()

        // ✅ use.inputPriority preset, videoformat
        // use.high preset thenset activeFormat runtime error
        session.sessionPreset = .inputPriority

        // configurecamerainput
        guard let device = CameraDeviceManager.shared.currentCamera else {
            session.commitConfiguration()
            print("❌ [VideoCameraSession] 没有可用相机")
            return
        }
        CameraInputConfigurator.shared.configureCameraInput(for: session, device: device)

        // configureaudioinput
        CameraInputConfigurator.shared.configureAudioInput(for: session)

        // configurevideodataoutput(used forpreview)
        // videomode, defaultensurerecordingquality, recordingconfigure
        videoDataOutput = CameraOutputConfigurator.shared.configureVideoDataOutput(for: session, discardsLateFrames: false)

        // configureaudiodataoutput
        audioDataOutput = CameraOutputConfigurator.shared.configureAudioDataOutput(for: session)

        // ✅ keyfix: session configuresetvideoformat
        // use pending configuredefaultconfigure, ensure session format
        let resolution = pendingResolution ?? Self.defaultResolution
        let frameRate = pendingFrameRate ?? Self.defaultFrameRate
        applyVideoFormat(to: device, resolution: resolution, frameRate: frameRate)

        session.commitConfiguration()

        // setoutput delegates
        setupOutputDelegates()

        print("✅ [VideoCameraSession] 视频 Session 配置完成")
    }

    /// session configurevideoformat(not beginConfiguration/commitConfiguration)
    private func applyVideoFormat(to device: AVCaptureDevice, resolution: CMVideoDimensions, frameRate: Int32) {
        guard let selectionResult = CameraFormatSelector.shared.selectBestFormat(
            for: device,
            desiredResolution: resolution,
            desiredFrameRate: frameRate
        ) else {
            print("⚠️ [VideoCameraSession] 未找到匹配的视频格式")
            return
        }

        do {
            try device.lockForConfiguration()
        } catch {
            print("❌ [VideoCameraSession] 锁定设备配置失败: \(error)")
            return
        }
        defer { device.unlockForConfiguration() }

        // validateand
        let supportedRanges = selectionResult.format.videoSupportedFrameRateRanges
        let targetFrameRate = Double(selectionResult.actualFrameRate)
        let resolvedFrameRate: Int32

        if supportedRanges.contains(where: { targetFrameRate >= $0.minFrameRate && targetFrameRate <= $0.maxFrameRate }) {
            resolvedFrameRate = selectionResult.actualFrameRate
        } else if let fallbackRange = supportedRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }),
                  fallbackRange.maxFrameRate > 0
        {
            resolvedFrameRate = max(1, Int32(fallbackRange.maxFrameRate))
        } else {
            resolvedFrameRate = Self.defaultFrameRate
        }

        device.activeFormat = selectionResult.format
        let duration = CMTime(value: 1, timescale: resolvedFrameRate)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        let dimensions = CMVideoFormatDescriptionGetDimensions(selectionResult.format.formatDescription)
        print("📹 [VideoCameraSession] 初始格式: \(dimensions.width)x\(dimensions.height)@\(resolvedFrameRate)fps")
    }

    override func setupOutputDelegates() {
        // setvideodataoutput delegate
        if let videoOutput = videoDataOutput,
           let delegate = videoSampleBufferDelegate
        {
            videoOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(
                label: "com.day1-labs.yoyo.camera.video.video",
                qos: .userInitiated
            ))
        }

        // setaudiodataoutput delegate
        if let audioOutput = audioDataOutput,
           let delegate = audioSampleBufferDelegate
        {
            audioOutput.setSampleBufferDelegate(delegate, queue: DispatchQueue(
                label: "com.day1-labs.yoyo.camera.video.audio",
                qos: .userInitiated
            ))
        }
    }

    override func updateVideoConfiguration(videoResolution: CGSize, videoFrameRate: Double) {
        let desiredResolution = CMVideoDimensions(width: Int32(videoResolution.width), height: Int32(videoResolution.height))
        let desiredFrameRate = Int32(videoFrameRate)

        print("🎥 [VideoCameraSession] 收到视频配置更新: \(desiredResolution.width)x\(desiredResolution.height)@\(desiredFrameRate)fps")

        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.pendingResolution = desiredResolution
            self.pendingFrameRate = desiredFrameRate
            print("🎥 [VideoCameraSession] 已缓存配置, session.isRunning=\(self.session.isRunning)")

            // if session in progress,
            if self.session.isRunning {
                self.applyPendingConfigurationIfNeeded()
            } else {
                print("🎥 [VideoCameraSession] Session 未运行，配置将在启动时应用")
            }
        }
    }

    /// onlycacheconfigure(`sessionQueue`), used formodeswitch
    func cacheVideoConfiguration(videoResolution: CGSize, videoFrameRate: Double) {
        let desiredResolution = CMVideoDimensions(width: Int32(videoResolution.width), height: Int32(videoResolution.height))
        let desiredFrameRate = Int32(videoFrameRate)
        pendingResolution = desiredResolution
        pendingFrameRate = desiredFrameRate
        print("🎥 [VideoCameraSession] 已缓存配置(同步): \(desiredResolution.width)x\(desiredResolution.height)@\(desiredFrameRate)fps")
    }

    private func applyPendingConfigurationIfNeeded() {
        guard let resolution = pendingResolution,
              let frameRate = pendingFrameRate,
              let device = CameraDeviceManager.shared.getCurrentCamera()
        else {
            print("⚠️ [VideoCameraSession] applyPendingConfigurationIfNeeded 跳过: resolution=\(String(describing: pendingResolution)), frameRate=\(String(describing: pendingFrameRate)), device=\(CameraDeviceManager.shared.getCurrentCamera() != nil)")
            return
        }

        print("🎥 [VideoCameraSession] 开始应用视频配置: \(resolution.width)x\(resolution.height)@\(frameRate)fps")

        // format
        if let selectionResult = CameraFormatSelector.shared.selectBestFormat(
            for: device,
            desiredResolution: resolution,
            desiredFrameRate: frameRate
        ) {
            applyFormatSelection(selectionResult, to: device)
        }
    }

    private func applyFormatSelection(_ result: FormatSelectionResult, to device: AVCaptureDevice) {
        // ✅ ensureno configuresuccessfully, completenotify(used forrestore, zoomstate)
        defer {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .videoFormatConfigurationDidComplete, object: nil)
            }
        }

        let supportedRanges = result.format.videoSupportedFrameRateRanges
        let rangesDescription = supportedRanges
            .map { String(format: "%.2f-%.2f", $0.minFrameRate, $0.maxFrameRate) }
            .joined(separator: ", ")
        let targetFrameRate = Double(result.actualFrameRate)

        let resolvedFrameRate: Int32
        if supportedRanges.contains(where: { targetFrameRate >= $0.minFrameRate && targetFrameRate <= $0.maxFrameRate }) {
            resolvedFrameRate = result.actualFrameRate
        } else if let fallbackRange = supportedRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }),
                  fallbackRange.maxFrameRate > 0
        {
            resolvedFrameRate = max(1, Int32(fallbackRange.maxFrameRate))
            print("⚠️ [VideoCameraSession] 目标帧率 \(result.actualFrameRate)fps 超出范围 [\(rangesDescription)]，回退至 \(fallbackRange.maxFrameRate)fps")
        } else {
            print("❌ [VideoCameraSession] 目标帧率 \(result.actualFrameRate)fps 无可用范围 [\(rangesDescription)]，跳过配置")
            return
        }

        // ✅ savecurrentzoom, becauseset activeFormat reset
        let currentZoomFactor = device.videoZoomFactor

        // ✅ fix: use session configureformat, session configuredevice runtime error
        // session in progress, beginConfiguration/commitConfiguration deviceconfigure
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        do {
            try device.lockForConfiguration()
        } catch {
            print("❌ [VideoCameraSession] 设置格式失败: \(error)")
            return
        }
        defer { device.unlockForConfiguration() }

        device.activeFormat = result.format
        let duration = CMTime(value: 1, timescale: resolvedFrameRate)
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        // ✅ restorezoom(formatrange)
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor)
        let restoredZoom = max(minZoom, min(maxZoom, currentZoomFactor))
        if restoredZoom != device.videoZoomFactor {
            device.videoZoomFactor = restoredZoom
            print("🔍 [VideoCameraSession] 恢复缩放因子: \(String(format: "%.2f", restoredZoom))x")
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(result.format.formatDescription)
        print("✅ [VideoCameraSession] 格式配置成功: \(dimensions.width)x\(dimensions.height)@\(resolvedFrameRate)fps")
    }

    /// set delegates
    func setVideoDataOutputDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        videoSampleBufferDelegate = delegate
        if isConfigured {
            setupOutputDelegates()
        }
    }

    func setAudioDataOutputDelegate(_ delegate: AVCaptureAudioDataOutputSampleBufferDelegate?) {
        audioSampleBufferDelegate = delegate
        if isConfigured {
            setupOutputDelegates()
        }
    }

    /// get output interfaces
    override func getVideoDataOutput() -> AVCaptureVideoDataOutput? {
        videoDataOutput
    }

    func getAudioDataOutput() -> AVCaptureAudioDataOutput? {
        audioDataOutput
    }
}
