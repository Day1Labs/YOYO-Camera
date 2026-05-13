@preconcurrency import AVFoundation

/// cameraoutputconfigure
/// management AVCaptureSession outputconfigure
final class CameraOutputConfigurator {
    static let shared = CameraOutputConfigurator()

    private init() {}

    /// configurephotooutput
    /// - Parameters:
    ///   - session: session
    ///   - device: currentcameradevice(used forconfigurehigh resolution)
    ///   - enableLive Photo: whether Live Photo
    /// - Returns: photooutput instances
    func configurePhotoOutput(for session: AVCaptureSession, device: AVCaptureDevice?, enableLivePhoto: Bool) -> AVCapturePhotoOutput? {
        print("📸 [CameraOutputConfigurator] 开始配置照片输出")

        // removephotooutput
        removeExistingPhotoOutput(from: session)

        let photoOutput = AVCapturePhotoOutput()

        guard session.canAddOutput(photoOutput) else {
            print("❌ [CameraOutputConfigurator] 无法添加照片输出")
            return nil
        }

        session.addOutput(photoOutput)
        print("✅ [CameraOutputConfigurator] 照片输出配置成功")

        // configure ProRAW
        if photoOutput.isAppleProRAWSupported {
            photoOutput.isAppleProRAWEnabled = true
            print("✅ [CameraOutputConfigurator] Apple ProRAW 已启用")
        } else {
            print("ℹ️ [CameraOutputConfigurator] 当前设备/格式不支持 Apple ProRAW")
        }

        // configure Live Photo
        configureLivePhoto(for: photoOutput, enabled: enableLivePhoto)

        // configurehigh resolution(only session videoinput)
        if hasVideoInput(in: session) {
            configureHighResolution(for: photoOutput, device: device)
        } else {
            print("⚠️ [CameraOutputConfigurator] Session 没有视频输入，跳过高分辨率配置")
        }

        return photoOutput
    }

    /// configurevideooutput
    /// - Parameter session: session
    /// - Returns: videooutput instances
    func configureMovieFileOutput(for session: AVCaptureSession) -> AVCaptureMovieFileOutput? {
        print("🎥 [CameraOutputConfigurator] 开始配置视频文件输出")

        // removevideooutput
        removeExistingMovieOutput(from: session)

        let movieOutput = AVCaptureMovieFileOutput()

        guard session.canAddOutput(movieOutput) else {
            print("❌ [CameraOutputConfigurator] 无法添加视频文件输出")
            return nil
        }

        session.addOutput(movieOutput)

        // configurevideo
        if let connection = movieOutput.connection(with: .video),
           connection.isVideoStabilizationSupported
        {
            connection.preferredVideoStabilizationMode = .auto
            print("✅ [CameraOutputConfigurator] 视频稳定已启用")
        }

        print("✅ [CameraOutputConfigurator] 视频文件输出配置成功")
        return movieOutput
    }

    /// configurevideodataoutput
    /// - Parameters:
    ///   - session: session
    ///   - discardsLateFrames: whether(preview true, recording false)
    /// - Returns: videodataoutput instances
    func configureVideoDataOutput(for session: AVCaptureSession, discardsLateFrames: Bool = true) -> AVCaptureVideoDataOutput? {
        print("📹 [CameraOutputConfigurator] 开始配置视频数据输出, discardsLateFrames: \(discardsLateFrames)")

        // checkwhether
        if let existingOutput = findExistingVideoDataOutput(in: session) {
            print("📋 [CameraOutputConfigurator] 视频数据输出已存在，更新配置并返回")
            existingOutput.alwaysDiscardsLateVideoFrames = discardsLateFrames
            return existingOutput
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = discardsLateFrames

        guard session.canAddOutput(videoOutput) else {
            print("❌ [CameraOutputConfigurator] 无法添加视频数据输出")
            return nil
        }

        session.addOutput(videoOutput)
        print("✅ [CameraOutputConfigurator] 视频数据输出配置成功")
        return videoOutput
    }

    /// configureaudiodataoutput
    /// - Parameter session: session
    /// - Returns: audiodataoutput instances
    func configureAudioDataOutput(for session: AVCaptureSession) -> AVCaptureAudioDataOutput? {
        print("🎤 [CameraOutputConfigurator] 开始配置音频数据输出")

        // checkwhether
        if let existingOutput = findExistingAudioDataOutput(in: session) {
            print("📋 [CameraOutputConfigurator] 音频数据输出已存在，返回现有实例")
            return existingOutput
        }

        let audioOutput = AVCaptureAudioDataOutput()

        guard session.canAddOutput(audioOutput) else {
            print("❌ [CameraOutputConfigurator] 无法添加音频数据输出")
            return nil
        }

        session.addOutput(audioOutput)
        print("✅ [CameraOutputConfigurator] 音频数据输出配置成功")
        return audioOutput
    }

    // MARK: - Private Methods

    /// removephotooutput
    private func removeExistingPhotoOutput(from session: AVCaptureSession) {
        for output in session.outputs {
            if output is AVCapturePhotoOutput {
                print("🗑️ [CameraOutputConfigurator] 移除现有照片输出")
                session.removeOutput(output)
            }
        }
    }

    /// removevideooutput
    private func removeExistingMovieOutput(from session: AVCaptureSession) {
        for output in session.outputs {
            if output is AVCaptureMovieFileOutput {
                print("🗑️ [CameraOutputConfigurator] 移除现有视频文件输出")
                session.removeOutput(output)
            }
        }
    }

    /// videodataoutput
    private func findExistingVideoDataOutput(in session: AVCaptureSession) -> AVCaptureVideoDataOutput? {
        session.outputs.first { $0 is AVCaptureVideoDataOutput } as? AVCaptureVideoDataOutput
    }

    /// audiodataoutput
    private func findExistingAudioDataOutput(in session: AVCaptureSession) -> AVCaptureAudioDataOutput? {
        session.outputs.first { $0 is AVCaptureAudioDataOutput } as? AVCaptureAudioDataOutput
    }

    /// check session whethervideoinput
    private func hasVideoInput(in session: AVCaptureSession) -> Bool {
        session.inputs.contains { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.video)
        }
    }

    /// configure Live Photo
    private func configureLivePhoto(for output: AVCapturePhotoOutput, enabled: Bool) {
        if output.isLivePhotoCaptureSupported {
            output.isLivePhotoCaptureEnabled = enabled
            print("✅ [CameraOutputConfigurator] Live Photo 配置: \(enabled)")
        } else {
            print("⚠️ [CameraOutputConfigurator] 不支持 Live Photo")
        }
    }

    /// configurehigh resolution
    private func configureHighResolution(for output: AVCapturePhotoOutput, device: AVCaptureDevice?) {
        guard let device else { return }

        if #available(iOS 16.0, *) {
            let format = device.activeFormat
            let supportedDimensions = format.supportedMaxPhotoDimensions
            if let bestDimensions = supportedDimensions.max(by: { lhs, rhs in
                let lhsArea = Int(lhs.width) * Int(lhs.height)
                let rhsArea = Int(rhs.width) * Int(rhs.height)
                return lhsArea < rhsArea
            }),
                bestDimensions.width > 0,
                bestDimensions.height > 0
            {
                output.maxPhotoDimensions = bestDimensions
                print("✅ [CameraOutputConfigurator] 高分辨率配置: \(bestDimensions.width)x\(bestDimensions.height)")
            }
        } else {
            output.isHighResolutionCaptureEnabled = true
            print("✅ [CameraOutputConfigurator] 高分辨率捕获已启用")
        }
    }
}
