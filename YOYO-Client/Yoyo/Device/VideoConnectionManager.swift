import AVFoundation
import UIKit

/// video connection manager - configuremanagementvideoconnectionorientation, mirroringproperties
final class VideoConnectionManager {
    // MARK: - Properties

    static let shared = VideoConnectionManager()

    private init() {}

    private weak var videoDataOutput: AVCaptureVideoDataOutput?
    private weak var currentCamera: AVCaptureDevice?
    var onConfigurationReady: (() -> Void)?

    /// video stabilization switch
    var stabilizationEnabled: Bool = false

    /// currentwhethervideocapturemode(onlyvideomodevideostabilization)
    var isVideoCaptureModeActive: Bool = false

    // MARK: - Configuration Methods

    func setVideoDataOutput(_ output: AVCaptureVideoDataOutput?) {
        videoDataOutput = output
    }

    func setCurrentCamera(_ camera: AVCaptureDevice?) {
        currentCamera = camera
    }

    // MARK: - Video Connection Configuration

    /// configure the orientation and mirroring settings of the video connection
    func configureVideoConnection() {
        guard let output = videoDataOutput,
              let connection = output.connection(with: .video)
        else { return }

        let orientation = OrientationManager.shared
        let isFrontCamera = currentCamera?.position == .front
        connection.videoOrientation = orientation.currentAVCaptureVideoOrientation
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isFrontCamera
        connection.isEnabled = true

        // configurestabilization(onlyvideomode; usecurrent SDK available mode)
        if let mode = preferredStabilizationMode(for: connection) {
            connection.preferredVideoStabilizationMode = mode
            print("🟢 [VideoConnectionManager] preferred=\(connection.preferredVideoStabilizationMode.rawValue), active=\(connection.activeVideoStabilizationMode.rawValue)")
        }

        notifyConfigurationReady()
    }

    private func preferredStabilizationMode(for connection: AVCaptureConnection) -> AVCaptureVideoStabilizationMode? {
        guard connection.isVideoStabilizationSupported else { return nil }

        // videocapturemode: (not)
        guard isVideoCaptureModeActive else {
            return AVCaptureVideoStabilizationMode.off
        }

        // videomode: systemauto; off
        return stabilizationEnabled ? AVCaptureVideoStabilizationMode.auto : AVCaptureVideoStabilizationMode.off
    }

    private func notifyConfigurationReady() {
        guard let callback = onConfigurationReady else { return }
        DispatchQueue.main.async {
            callback()
        }
    }

    // MARK: - Utility Methods

    func isConfigurationValid() -> Bool {
        videoDataOutput != nil &&
            currentCamera != nil &&
            videoDataOutput?.connection(with: .video) != nil
    }
}
