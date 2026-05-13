import AVFoundation

/// SampleBuffer controller, UI data
final class SampleBufferController: NSObject {
    static let shared = SampleBufferController(
        previewRenderController: .shared,
        sessionManager: .shared,
        audioManager: .shared
    )

    // dependencies
    private var captureService: CameraCaptureService { .shared }
    private weak var previewRenderController: PreviewRenderController?
    private weak var audioManager: AudioManager?
    private weak var sessionManager: CameraSessionManager?

    /// queue: video/audio, real-time
    private let videoQueue = DispatchQueue(
        label: "com.day1-labs.yoyo.sampleBuffer.video",
        qos: .userInitiated
    )
    private let audioQueue = DispatchQueue(
        label: "com.day1-labs.yoyo.sampleBuffer.audio",
        qos: .userInitiated
    )

    private init(
        previewRenderController: PreviewRenderController,
        sessionManager: CameraSessionManager,
        audioManager: AudioManager?
    ) {
        self.previewRenderController = previewRenderController
        self.sessionManager = sessionManager
        self.audioManager = audioManager
        super.init()
    }

    // MARK: - Private Helpers

    func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard sessionManager?.isVideoConnectionReady == true else { return }

        previewRenderController?.enqueue(sampleBuffer: sampleBuffer)
        captureService.appendVideoSampleBuffer(sampleBuffer)
    }

    func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard audioManager?.isAudioMuted != true else { return }

        captureService.appendAudioSampleBuffer(sampleBuffer)
        audioManager?.processAudioBuffer(sampleBuffer)
    }
}

// MARK: - AVCapture Delegates

extension SampleBufferController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            videoQueue.async { [weak self] in
                self?.handleVideoSampleBuffer(sampleBuffer)
            }
        } else if output is AVCaptureAudioDataOutput {
            audioQueue.async { [weak self] in
                self?.handleAudioSampleBuffer(sampleBuffer)
            }
        }
    }
}
