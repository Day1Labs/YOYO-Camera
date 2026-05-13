@preconcurrency import AVFoundation

/// camerainputconfigure
/// management AVCaptureSession inputdeviceconfigure
final class CameraInputConfigurator {
    static let shared = CameraInputConfigurator()

    private init() {}

    /// configurecamerainputdevice
    /// - Parameters:
    ///   - session: session
    ///   - device: cameradevice
    /// - Returns: configureresult
    @discardableResult
    func configureCameraInput(for session: AVCaptureSession, device: AVCaptureDevice?) -> Bool {
        guard let device else {
            print("❌ [CameraInputConfigurator] 没有可用的相机设备")
            return false
        }

        print("🎥 [CameraInputConfigurator] 开始配置相机输入: \(device.deviceType.rawValue)")

        do {
            let input = try AVCaptureDeviceInput(device: device)

            // removeinput
            removeExistingInputs(from: session, mediaType: .video)

            if session.canAddInput(input) {
                session.addInput(input)
                print("✅ [CameraInputConfigurator] 相机输入配置成功")
                return true
            } else {
                print("❌ [CameraInputConfigurator] 无法添加相机输入")
                return false
            }
        } catch {
            print("❌ [CameraInputConfigurator] 创建相机输入失败: \(error)")
            return false
        }
    }

    /// configureaudioinputdevice
    /// - Parameter session: session
    /// - Returns: configureresult
    @discardableResult
    func configureAudioInput(for session: AVCaptureSession) -> Bool {
        // check
        guard checkAudioPermission() else {
            print("❌ [CameraInputConfigurator] 没有麦克风权限")
            return false
        }

        // checkwhetheraudioinput
        guard !hasAudioInput(in: session) else {
            print("📋 [CameraInputConfigurator] 音频输入已存在，跳过配置")
            return true
        }

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("⚠️ [CameraInputConfigurator] 无法获取音频设备")
            return false
        }

        print("🎤 [CameraInputConfigurator] 开始配置音频输入")

        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)

            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                print("✅ [CameraInputConfigurator] 音频输入配置成功")
                return true
            } else {
                print("⚠️ [CameraInputConfigurator] 无法添加音频输入")
                return false
            }
        } catch {
            print("❌ [CameraInputConfigurator] 创建音频输入失败: \(error.localizedDescription)")
            return false
        }
    }

    private func checkAudioPermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            // not yet, upper-layerbusiness logic
            // here false configurefailed
            return false
        default:
            return false
        }
    }

    /// removeaudioinputdevice
    /// - Parameter session: session
    func removeAudioInput(from session: AVCaptureSession) {
        removeExistingInputs(from: session, mediaType: .audio)
    }

    /// removeinput
    /// - Parameters:
    ///   - session: session
    ///   - mediaType:
    private func removeExistingInputs(from session: AVCaptureSession, mediaType: AVMediaType) {
        for input in session.inputs {
            guard let deviceInput = input as? AVCaptureDeviceInput,
                  deviceInput.device.hasMediaType(mediaType) else { continue }

            print("🗑️ [CameraInputConfigurator] 移除现有输入: \(mediaType.rawValue)")
            session.removeInput(input)
        }
    }

    /// checkwhetheraudioinput
    /// - Parameter session: session
    /// - Returns: whetheraudioinput
    private func hasAudioInput(in session: AVCaptureSession) -> Bool {
        session.inputs.contains { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.audio)
        }
    }
}
