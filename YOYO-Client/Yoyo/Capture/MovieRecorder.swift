import AVFoundation
import CoreImage
import CoreMedia
import UIKit

// MARK: - recording configuration struct

struct RecordingConfig {
    let videoFrameRate: Double
    let videoResolution: CameraSettingsState.VideoResolution
    let videoSaveFormat: CameraSettingsState.VideoSaveFormat
    let fileNamingTemplate: String
    let fileNamingPrefix: String
    let isOriginal: Bool // whetheroriginalvideo(used forgeneratenot)

    init(videoFrameRate: Double,
         videoResolution: CameraSettingsState.VideoResolution,
         videoSaveFormat: CameraSettingsState.VideoSaveFormat,
         fileNamingTemplate: String,
         fileNamingPrefix: String,
         isOriginal: Bool = false)
    {
        self.videoFrameRate = videoFrameRate
        self.videoResolution = videoResolution
        self.videoSaveFormat = videoSaveFormat
        self.fileNamingTemplate = fileNamingTemplate
        self.fileNamingPrefix = fileNamingPrefix
        self.isOriginal = isOriginal
    }
}

protocol MovieRecorderDelegate: AnyObject {
    func movieRecorder(_ recorder: MovieRecorder, didStartRecordingTo url: URL)
    func movieRecorder(_ recorder: MovieRecorder, didFinishRecordingTo url: URL, error: Error?)
}

/// Manages AVAssetWriter components and their lifecycle.
private final class WriterPipeline {
    private(set) var assetWriter: AVAssetWriter?
    private(set) var videoInput: AVAssetWriterInput?
    private(set) var audioInput: AVAssetWriterInput?
    private(set) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    var status: AVAssetWriter.Status? { assetWriter?.status }
    var isConfigured: Bool { videoInput != nil }
    var writerError: Error? { assetWriter?.error }

    func prepareWriter(outputURL: URL, fileType: AVFileType) -> Bool {
        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
            assetWriter = writer
            return true
        } catch {
            print("❌ [WriterPipeline] 创建 AssetWriter 失败: \(error.localizedDescription)")
            return false
        }
    }

    func configureWriter(size: CGSize,
                         videoSettings: [String: Any],
                         transform: CGAffineTransform?,
                         audioSettings: [String: Any]?) -> Bool
    {
        guard let writer = assetWriter else {
            print("❌ [WriterPipeline] AssetWriter 未初始化")
            return false
        }

        if isConfigured {
            return true
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if let transform {
            videoInput.transform = transform
        }

        guard writer.canAdd(videoInput) else {
            print("❌ [WriterPipeline] 无法添加视频输入")
            return false
        }
        writer.add(videoInput)
        self.videoInput = videoInput

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        if let audioSettings {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
                print("✅ [WriterPipeline] 音频输入添加成功")
            } else {
                print("⚠️ [WriterPipeline] 无法添加音频输入，将录制无声视频")
            }
        }

        guard writer.startWriting() else {
            let error = writer.error
            print("❌ [WriterPipeline] 无法开始写入: \(error?.localizedDescription ?? "未知错误")")
            if let error {
                print("🔍 [WriterPipeline] 详细错误信息: \(error)")
            }
            return false
        }

        print("✅ [WriterPipeline] AssetWriter 配置完成，状态: \(writer.status.rawValue)")
        return true
    }

    func startSession(at time: CMTime) {
        assetWriter?.startSession(atSourceTime: time)
    }

    func markInputsFinished() {
        if let videoInput, videoInput.isReadyForMoreMediaData {
            videoInput.markAsFinished()
        }
        if let audioInput, audioInput.isReadyForMoreMediaData {
            audioInput.markAsFinished()
        }
    }

    func hasPixelBufferAdaptor() -> Bool {
        pixelBufferAdaptor != nil
    }

    func isVideoInputReady() -> Bool {
        videoInput?.isReadyForMoreMediaData ?? false
    }

    func isAudioInputReady() -> Bool {
        audioInput?.isReadyForMoreMediaData ?? false
    }

    func pixelBufferPool() -> CVPixelBufferPool? {
        pixelBufferAdaptor?.pixelBufferPool
    }

    func appendVideoBuffer(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard let adaptor = pixelBufferAdaptor else { return false }
        return adaptor.append(buffer, withPresentationTime: time)
    }

    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return false }
        return audioInput.append(sampleBuffer)
    }

    func finishWriting(completion: @escaping () -> Void) {
        assetWriter?.finishWriting(completionHandler: completion)
    }

    func reset() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
    }
}

final class MovieRecorder {
    // MARK: - Properties

    weak var delegate: MovieRecorderDelegate?

    /// session manager reference(used for captureSession)
    private weak var sessionManager: CameraSessionManager?

    /// orientation manager reference(used forvideoorientationset)
    private weak var orientationManager: OrientationManager?

    // Shared components
    private let metadataBuilder = MetadataBuilder.shared
    private let pipeline = WriterPipeline()

    /// whether recording is in progress
    private(set) var isRecording = false

    /// URL of the currently recorded video
    private(set) var currentVideoURL: URL?

    /// current recording configuration
    private var currentRecordingConfig: RecordingConfig?

    // time management
    private var isFirstFrame = true
    private var sessionStarted = false
    private var recordingStartFrameCounter: UInt32 = 0

    /// video size(get)
    private var videoSize: CGSize?

    /// CoreImage context(used forfilter)
    private let ciContext: CIContext

    /// use - videouse ITU-R BT.709
    private let renderColorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
    private let workingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// performance monitoring
    private var frameDropCount = 0

    /// frame counter(used forgenerate frameSeed)
    private var frameCounter: UInt32 = 0

    /// serial queue dedicated to recording, andblockingmain thread
    private let recordingQueue = DispatchQueue(label: "com.day1-labs.yoyo.movieRecorder.queue", qos: .userInteractive)

    // MARK: - Initialization

    init(
        orientationManager: OrientationManager?,
        sessionManager: CameraSessionManager? = nil
    ) {
        self.sessionManager = sessionManager
        self.orientationManager = orientationManager

        // create CIContext(use GPU)
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice, options: [
                .workingColorSpace: workingColorSpace,
                .outputColorSpace: renderColorSpace,
                .cacheIntermediates: true,
            ])
        } else {
            ciContext = CIContext(options: [
                .workingColorSpace: workingColorSpace,
                .outputColorSpace: renderColorSpace,
                .cacheIntermediates: true,
            ])
        }
    }

    /// target frame rate(currentrecordingconfigureget)- used forconfigure
    private var targetFrameRate: Double {
        currentRecordingConfig?.videoFrameRate ?? 30.0
    }

    /// validate the actual frame rate output by the device
    private func validateDeviceFrameRate() -> Double? {
        guard let currentCamera = CameraDeviceManager.shared.getCurrentCamera()
        else {
            print("⚠️ [MovieRecorder] 无法获取当前设备")
            return currentRecordingConfig?.videoFrameRate ?? 30.0
        }
        // key
        if let session = sessionManager?.captureSession {
            let dim = CMVideoFormatDescriptionGetDimensions(currentCamera.activeFormat.formatDescription)
            print("🟡 [实时检查-MovieRecorder] activeFormat=\(dim.width)x\(dim.height), min=\(currentCamera.activeVideoMinFrameDuration), max=\(currentCamera.activeVideoMaxFrameDuration), sessionPreset=\(session.sessionPreset)")
        }

        let minFrameDuration = currentCamera.activeVideoMinFrameDuration
        let maxFrameDuration = currentCamera.activeVideoMaxFrameDuration

        if minFrameDuration.value > 0, maxFrameDuration.value > 0 {
            let minFrameRate = Double(minFrameDuration.timescale) / Double(minFrameDuration.value)
            let maxFrameRate = Double(maxFrameDuration.timescale) / Double(maxFrameDuration.value)
            let actualFrameRate = (minFrameRate + maxFrameRate) / 2.0

            print("🔍 [MovieRecorder] 设备实际帧率检测: \(actualFrameRate) fps (范围: \(minFrameRate)-\(maxFrameRate))")
            return actualFrameRate
        }

        // ifno getdevice, configuretarget frame rate
        return currentRecordingConfig?.videoFrameRate ?? 30.0
    }

    deinit {
        print("🗑️ [MovieRecorder] deinit - 清理资源")
        stopRecording()
    }

    // MARK: - Public Methods

    /// start recording
    func startRecording(with config: RecordingConfig) -> Bool {
        recordingQueue.sync {
            guard !isRecording else {
                print("⚠️ [MovieRecorder] 已经在录制中")
                return false
            }

            // saverecordingconfigure
            currentRecordingConfig = config
            // recording
            if let currentCamera = CameraDeviceManager.shared.getCurrentCamera(), let session = sessionManager?.captureSession {
                let dim = CMVideoFormatDescriptionGetDimensions(currentCamera.activeFormat.formatDescription)
                print("🟡 [采集入口检查-MovieRecorder] activeFormat=\(dim.width)x\(dim.height), min=\(currentCamera.activeVideoMinFrameDuration), max=\(currentCamera.activeVideoMaxFrameDuration), sessionPreset=\(session.sessionPreset)")
            }

            // createtemporary URL
            let tempDir = FileManager.default.temporaryDirectory

            // userecordingconfigureformat
            var fileName = FileNameGenerator.shared.generateFullFileName(
                template: currentRecordingConfig?.fileNamingTemplate ?? "{prefix}_{timestamp}_{type}",
                prefix: currentRecordingConfig?.fileNamingPrefix ?? "YOYO",
                fileType: .video,
                fileFormat: .mov
            )

            // iforiginalvideo, add "_Original"
            if config.isOriginal {
                let fileExtension = (fileName as NSString).pathExtension
                let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension
                fileName = "\(fileNameWithoutExtension)_Original.\(fileExtension)"
            }

            let fileURL = tempDir.appendingPathComponent(fileName)

            // can
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🗑️ [MovieRecorder] 删除旧文件: \(fileURL.lastPathComponent)")
                } catch {
                    print("⚠️ [MovieRecorder] 无法删除旧文件: \(error.localizedDescription)")
                }
            }

            currentVideoURL = fileURL

            print("🎬 [MovieRecorder] 开始录制: \(fileURL.path)")
            let fileType = config.videoSaveFormat.fileType
            print("🎬 [MovieRecorder] 第一阶段：创建基础 AssetWriter - URL: \(fileURL.path), 格式: \(fileType)")

            let phase1Success = pipeline.prepareWriter(outputURL: fileURL, fileType: fileType)
            if !phase1Success {
                print("❌ [MovieRecorder] 第一阶段失败")
                // : herenot stopRecordingWithError, because delegate can prepare, sync
                return false
            }

            print("✅ [MovieRecorder] 第一阶段成功，等待第一帧获取实际尺寸")

            isRecording = true
            isFirstFrame = true
            sessionStarted = false // resetsession

            // notify
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.movieRecorder(self, didStartRecordingTo: fileURL)
            }

            return true
        }
    }

    /// stop recording
    func stopRecording() {
        recordingQueue.async { [weak self] in
            guard let strongSelf = self, strongSelf.isRecording else { return }

            guard let status = strongSelf.pipeline.status else {
                print("⚠️ [MovieRecorder] AssetWriter 未初始化，直接清理")
                strongSelf.isRecording = false
                strongSelf.cleanup()
                return
            }

            if status == .unknown {
                // if(not yet successfullydata), stop, not wait
                if strongSelf.isFirstFrame {
                    print("⚠️ [MovieRecorder] 停止录制时状态为 unknown 且未写入任何帧，视为录制失败或取消")
                    strongSelf.isRecording = false
                    strongSelf.cleanup()

                    // triggercompletecallback(error)
                    let error = NSError(domain: "MovieRecorder", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "录制未开始（无数据写入）",
                    ])

                    if let outputURL = strongSelf.currentVideoURL {
                        DispatchQueue.main.async {
                            strongSelf.delegate?.movieRecorder(strongSelf, didFinishRecordingTo: outputURL, error: error)
                        }
                    }
                    return
                }

                print("⏳ [MovieRecorder] 等待 AssetWriter 状态变化...")
                // delay 100ms
                strongSelf.recordingQueue.asyncAfter(deadline: .now() + 0.1) { [weak strongSelf] in
                    strongSelf?.stopRecording()
                }
                return
            }

            strongSelf.isRecording = false

            print("🎬 [MovieRecorder] 停止录制，writer 状态: \(status.rawValue)")

            strongSelf.pipeline.markInputsFinished()

            guard let outputURL = strongSelf.currentVideoURL else {
                print("⚠️ [MovieRecorder] 输出 URL 为空")
                strongSelf.cleanup()
                return
            }

            switch status {
            case .writing:
                strongSelf.pipeline.finishWriting { [weak strongSelf] in
                    DispatchQueue.main.async {
                        strongSelf?.handleWriterCompletion(at: outputURL)
                    }
                }
            case .completed, .failed, .cancelled:
                print("⚠️ [MovieRecorder] AssetWriter 已处于结束状态: \(status.rawValue)，触发完成回调")
                DispatchQueue.main.async {
                    strongSelf.handleWriterCompletion(at: outputURL)
                }
            case .unknown:
                print("⚠️ [MovieRecorder] AssetWriter 状态仍为 unknown，直接清理")
                strongSelf.cleanup()
            @unknown default:
                print("⚠️ [MovieRecorder] AssetWriter 未知状态，直接清理")
                strongSelf.cleanup()
            }
        }
    }

    @MainActor
    private func handleWriterCompletion(at url: URL) {
        let status = pipeline.status
        let writerError = pipeline.writerError

        if status == .completed {
            print("✅ [MovieRecorder] 录制完成: \(url.path)")
            delegate?.movieRecorder(self, didFinishRecordingTo: url, error: nil)
            cleanup()
            return
        }

        let error = writerError ?? NSError(domain: "MovieRecorder", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "视频录制失败，AssetWriter状态: \(status?.rawValue ?? -1)",
        ])

        print("❌ [MovieRecorder] 录制失败: \(error.localizedDescription)")
        if let status {
            print("🔍 [MovieRecorder] Writer状态: \(status.rawValue), 错误详情: \(error)")
        }

        delegate?.movieRecorder(self, didFinishRecordingTo: url, error: error)
        cleanup()
    }

    /// process video frames(sample buffer)
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // useserialqueue, and
        recordingQueue.async { [weak self] in
            autoreleasepool {
                guard let self, self.isRecording else { return }
                self.processVideoFrame(sampleBuffer)
            }
        }
    }

    /// internal method for processing video frames
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard ensureWriterConfigured(for: sampleBuffer) else { return }
        startSessionIfNeeded(with: sampleBuffer)
        renderAndAppendVideoFrame(sampleBuffer)
    }

    private func ensureWriterConfigured(for sampleBuffer: CMSampleBuffer) -> Bool {
        if videoSize != nil {
            guard pipeline.isConfigured else {
                print("⏳ [MovieRecorder] AssetWriter 正在配置中，跳过帧")
                return false
            }

            guard pipeline.status == .writing else {
                print("⚠️ [MovieRecorder] AssetWriter 状态: \(pipeline.status?.rawValue ?? -1)，等待写入")
                return false
            }

            return true
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ [MovieRecorder] 无法获取 image buffer 用于初始化")
            stopRecordingWithError(NSError(domain: "MovieRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法读取首帧图像",
            ]))
            return false
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        guard width > 0, height > 0 else {
            print("❌ [MovieRecorder] 检测到无效的视频尺寸: \(width)x\(height)")
            stopRecordingWithError(NSError(domain: "MovieRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "检测到无效的视频尺寸",
            ]))
            return false
        }

        let deviceOrientation = orientationManager?.currentDeviceOrientation ?? .unknown

        print("📹 [MovieRecorder] 第一帧分析:")
        print("   - 原始帧尺寸: \(width)x\(height)")
        print("   - 设备方向: \(deviceOrientation.rawValue) (\(deviceOrientation))")

        let evenWidth = width - (width % 2)
        let evenHeight = height - (height % 2)

        // 16, 4K videocan cropping edge/green edge/misalignment
        let alignedWidth = (evenWidth + 15) / 16 * 16
        let alignedHeight = evenHeight // onlycan

        let finalSize = CGSize(width: alignedWidth, height: alignedHeight)

        videoSize = finalSize
        print("📹 [MovieRecorder] 检测到视频尺寸: \(width)x\(height) -> 调整为: \(alignedWidth)x\(alignedHeight) (16字节对齐)")

        guard configureWriter(with: finalSize) else {
            print("❌ [MovieRecorder] 第二阶段失败 - Writer状态: \(pipeline.status?.rawValue ?? -1)")
            if let error = pipeline.writerError {
                print("🔍 [MovieRecorder] Writer错误详情: \(error)")
            }
            stopRecordingWithError(NSError(domain: "MovieRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法配置视频写入器",
            ]))
            return false
        }

        print("✅ [MovieRecorder] 第二阶段成功 - Writer状态: \(pipeline.status?.rawValue ?? -1)")
        return true
    }

    private func startSessionIfNeeded(with sampleBuffer: CMSampleBuffer) {
        guard isFirstFrame, pipeline.status == .writing else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        pipeline.startSession(at: presentationTime)
        isFirstFrame = false
        sessionStarted = true
        print("📸 [MovieRecorder] 开始会话，时间: \(presentationTime.seconds)")
    }

    /// stop recording and report an error
    private func stopRecordingWithError(_ error: Error) {
        isRecording = false
        cleanup()

        DispatchQueue.main.async { [weak self] in
            guard let self, let outputURL = self.currentVideoURL else { return }
            self.delegate?.movieRecorder(self, didFinishRecordingTo: outputURL, error: error)
        }
    }

    /// process audio frames
    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        recordingQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRecording,
                  self.sessionStarted,
                  self.pipeline.status == .writing else { return }

            guard self.pipeline.isAudioInputReady() else { return }

            if !self.pipeline.appendAudioBuffer(sampleBuffer) {
                print("⚠️ [MovieRecorder] 无法写入音频帧")
            }
        }
    }

    // MARK: - Private Methods

    private func configureWriter(with size: CGSize) -> Bool {
        let videoSettings = createVideoOutputSettings(size: size)
        print("🎬 [MovieRecorder] 视频设置: \(videoSettings)")

        let audioSettings = createAudioOutputSettings()
        let orientation = orientationManager?.currentDeviceOrientation ?? .unknown
        let transform = transformForOrientation(orientation)

        print("🎬 [MovieRecorder] 视频帧尺寸: \(size), transform: \(transform)")

        let configured = pipeline.configureWriter(
            size: size,
            videoSettings: videoSettings,
            transform: transform,
            audioSettings: audioSettings
        )

        // Writerconfiguresuccessfully,
        if configured {
            prewarmPixelBufferPool(count: 8)
        }

        return configured
    }

    /// , create PixelBuffer
    private func prewarmPixelBufferPool(count: Int) {
        guard let pool = pipeline.pixelBufferPool() else { return }
        for _ in 0 ..< count {
            var pb: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            if status != kCVReturnSuccess {
                print("⚠️ [MovieRecorder] 像素缓冲池预热失败，status=\(status)")
                break
            }
            // release, letavailable
            pb = nil
        }
        print("✅ [MovieRecorder] 像素缓冲池预热完成: \(count) 个缓冲")
    }

    private func renderAndAppendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard pipeline.status == .writing else { return }

        guard pipeline.isVideoInputReady() else {
            print("⚠️ [MovieRecorder] videoInput not ready for more media data")
            return
        }

        guard pipeline.hasPixelBufferAdaptor() else {
            print("⚠️ [MovieRecorder] pixelBufferAdaptor is nil")
            return
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ [MovieRecorder] 无法获取 image buffer")
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        guard let pool = pipeline.pixelBufferPool() else {
            print("⚠️ [MovieRecorder] pixelBufferPool is nil")
            return
        }

        let sourceImage = CIImage(cvPixelBuffer: imageBuffer)
        let filteredImage = applyFilter(to: sourceImage)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

        guard status == kCVReturnSuccess, let outputBuffer = pixelBuffer else {
            print("⚠️ [MovieRecorder] 无法创建 pixel buffer")
            return
        }

        // Calculate scale and transform to fit the output buffer (Aspect Fill)
        let destinationWidth = CGFloat(CVPixelBufferGetWidth(outputBuffer))
        let destinationHeight = CGFloat(CVPixelBufferGetHeight(outputBuffer))
        let destinationSize = CGSize(width: destinationWidth, height: destinationHeight)

        let imageExtent = filteredImage.extent
        let scaleX = destinationWidth / imageExtent.width
        let scaleY = destinationHeight / imageExtent.height
        let scale = max(scaleX, scaleY)

        // Calculate centering translation
        let tx = (destinationWidth - imageExtent.width * scale) / 2 - imageExtent.origin.x * scale
        let ty = (destinationHeight - imageExtent.height * scale) / 2 - imageExtent.origin.y * scale

        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))

        let finalImageToRender = filteredImage.transformed(by: transform)

        let destinationRect = CGRect(origin: .zero, size: destinationSize)
        // usepreview sRGB, auto
        ciContext.render(finalImageToRender, to: outputBuffer, bounds: destinationRect, colorSpace: renderColorSpace)

        guard pipeline.isVideoInputReady() else {
            frameDropCount += 1
            print("⚠️ [MovieRecorder] 写入时状态变化，丢弃帧 (总丢帧: \(frameDropCount))")
            return
        }

        if !pipeline.appendVideoBuffer(outputBuffer, at: presentationTime) {
            print("⚠️ [MovieRecorder] 写入帧失败，时间: \(presentationTime.seconds)")
        }
    }

    /// filter(ifconfigurefilteroriginal)
    private func applyFilter(to image: CIImage) -> CIImage {
        // recordingfilter(isOriginal)
        if currentRecordingConfig?.isOriginal == true {
            return image
        }
        // useframe countergenerate frameSeed, ensurevideo
        let currentFrameSeed = frameCounter
        frameCounter &+= 1 // use, auto
        return FilterManager.shared.applyFilter(to: image, frameSeed: currentFrameSeed, quality: .preview)
    }

    /// createvideooutputset(useconfigure)
    private func createVideoOutputSettings(size: CGSize?) -> [String: Any] {
        // validatedeviceset
        let deviceFrameRate = validateDeviceFrameRate() ?? 30.0
        let targetFrameRate = targetFrameRate

        // usedevice, not then 30fps
        let effectiveFrameRate = deviceFrameRate

        if abs(deviceFrameRate - targetFrameRate) > 1.0 {
            print("⚠️ [MovieRecorder] 设备帧率 \(deviceFrameRate) 与目标帧率 \(targetFrameRate) 不匹配，使用设备帧率: \(effectiveFrameRate)")
        } else {
            print("✅ [MovieRecorder] 帧率验证通过: \(effectiveFrameRate) fps")
        } // useconfigure, ifuseconfiguredefault
        let dimensions: CGSize
        if let size {
            dimensions = size
        } else {
            dimensions = currentRecordingConfig?.videoResolution.dimensions ?? CGSize(width: 1920, height: 1080)
        }

        // ensure(video)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        let evenWidth = width - (width % 2)
        let evenHeight = height - (height % 2)

        // ensureminimum, not maximum
        let finalWidth = max(evenWidth, 320) // minimum
        let finalHeight = max(evenHeight, 240) // minimum

        // recordingconfigure
        let resolution = currentRecordingConfig?.videoResolution ?? .hd1080
        var bitRate: Int
        switch resolution {
        case .hd720:
            bitRate = 10_000_000 // 720p: 10 Mbps
        case .hd1080:
            bitRate = 25_000_000 // 1080p: 25 Mbps
        case .hd4k:
            bitRate = 55_000_000 // 4K: 55 Mbps
        }

        // Apply bitrate compensation for high frame rates
        if effectiveFrameRate > 30 {
            let multiplier = effectiveFrameRate / 30.0
            // 60fps 1.5 can, not need to,
            let adjustedMultiplier = 1.0 + (multiplier - 1.0) * 0.6
            bitRate = Int(Double(bitRate) * adjustedMultiplier)
            // 4K60 range 60–80 Mbps
            if resolution == .hd4k, effectiveFrameRate >= 60.0 {
                bitRate = min(max(bitRate, 60_000_000), 80_000_000)
            }
        }

        // use HEVC delayconfigure
        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoMaxKeyFrameIntervalKey: Int(effectiveFrameRate * 2), // 2 secondskey
            AVVideoExpectedSourceFrameRateKey: effectiveFrameRate,
            AVVideoAllowFrameReorderingKey: false,
            // Note: HEVC usually does not require `ProfileLevel` to be set explicitly; some SDKs do not provide HEVC profile constants
        ]

        print("🎬 [MovieRecorder] 编码器配置 - 分辨率: \(finalWidth)x\(finalHeight), 帧率: \(effectiveFrameRate) fps, 码率: \(Double(bitRate) / 1_000_000.0) Mbps, Codec: HEVC")

        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: finalWidth,
            AVVideoHeightKey: finalHeight,
            AVVideoCompressionPropertiesKey: compressionProperties,
        ]
    }

    /// create audio output settings
    /// use an audio quality configuration close to the native iOS camera
    private func createAudioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000, // 256 kbps, nativecameraquality
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
        ]
    }

    /// get the transform matrix from the orientation
    private func transformForOrientation(_ orientation: UIDeviceOrientation) -> CGAffineTransform {
        switch orientation {
        case .portrait:
            return .identity
        case .portraitUpsideDown:
            return CGAffineTransform(rotationAngle: .pi)
        case .landscapeRight:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .landscapeLeft:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .faceUp, .faceDown, .unknown:
            return .identity
        @unknown default:
            return .identity
        }
    }

    /// clean up
    private func cleanup() {
        pipeline.reset()

        isFirstFrame = true
        sessionStarted = false
        videoSize = nil
        frameDropCount = 0
        currentRecordingConfig = nil

        print("🧹 [MovieRecorder] 资源清理完成")
    }
}
