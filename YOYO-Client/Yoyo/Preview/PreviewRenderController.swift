import AVFoundation
import Combine
import CoreImage
import Metal

/// managementpreview, backgroundmain thread.
final class PreviewRenderController {
    static let shared = PreviewRenderController()

    struct Configuration {
        /// queue QoS, defaultuse userInteractive real-time.
        var renderQueueQoS: DispatchQoS = .userInteractive
    }

    private let lock = NSLock()
    private let renderQueue: DispatchQueue

    private var pendingSampleBuffer: CMSampleBuffer?
    private var isRendering = false

    private weak var metalLayer: CAMetalLayer?
    private let filterRenderer: CameraFilterRenderer
    private var configuration: Configuration

    /// successfullyand, updateoperation.
    let frameSubject = PassthroughSubject<CMSampleBuffer, Never>()

    /// callback, available.
    var onRenderDurationMeasured: ((_ duration: CFTimeInterval) -> Void)?

    private init(filterRenderer: CameraFilterRenderer = .shared, configuration: Configuration = .init()) {
        self.filterRenderer = filterRenderer
        self.configuration = configuration
        renderQueue = DispatchQueue(
            label: "com.day1-labs.yoyo.preview.render.queue",
            qos: configuration.renderQueueQoS
        )
    }

    func updateConfiguration(_ configuration: Configuration) {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }

    func attach(to metalLayer: CAMetalLayer?) {
        lock.lock()
        self.metalLayer = metalLayer
        lock.unlock()
    }

    func enqueue(sampleBuffer: CMSampleBuffer) {
        lock.lock()
        pendingSampleBuffer = sampleBuffer
        let shouldSchedule = !isRendering
        lock.unlock()

        if shouldSchedule {
            scheduleRender()
        }
    }

    func clear() {
        lock.lock()
        pendingSampleBuffer = nil
        lock.unlock()
    }

    /// resetstate(App backgroundrestore, isRendering)
    func resetRenderingState() {
        lock.lock()
        isRendering = false
        pendingSampleBuffer = nil
        lock.unlock()
    }

    private func scheduleRender() {
        lock.lock()
        guard !isRendering, let buffer = pendingSampleBuffer, let layer = metalLayer else {
            lock.unlock()
            return
        }
        isRendering = true
        pendingSampleBuffer = nil
        lock.unlock()

        renderQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let start = CACurrentMediaTime()
                guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
                    self.finishRendering()
                    return
                }

                let sourceImage = CIImage(cvPixelBuffer: imageBuffer)
                guard let commandBuffer = self.filterRenderer.renderPreview(to: layer, with: sourceImage) else {
                    self.finishRendering()
                    return
                }

                commandBuffer.addCompletedHandler { [weak self] _ in
                    self?.handleRenderCompletion(startTime: start, sampleBuffer: buffer)
                }
                commandBuffer.commit()
            }
        }
    }

    private func handleRenderCompletion(startTime: CFTimeInterval, sampleBuffer: CMSampleBuffer) {
        let duration = CACurrentMediaTime() - startTime
        onRenderDurationMeasured?(duration)
        frameSubject.send(sampleBuffer)
        finishRendering()
    }

    private func finishRendering() {
        lock.lock()
        isRendering = false
        let hasPending = pendingSampleBuffer != nil
        lock.unlock()

        if hasPending {
            scheduleRender()
        }
    }
}
