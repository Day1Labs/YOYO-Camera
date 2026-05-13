import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import UIKit

/// moviefilterprocessor - dedicatedmovie/videofilter
final class MovieFilterProcessor {
    // MARK: - Properties

    private let filterManager = FilterManager.shared
    private let renderingContext: CIContext
    private let processingQueue: DispatchQueue

    // MARK: - Initialization

    init() {
        // createcontext
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            renderingContext = CIContext(mtlDevice: metalDevice, options: [
                .cacheIntermediates: true,
                .useSoftwareRenderer: false, // ensureuse GPU
                .highQualityDownsample: false, // accelerate downsampling
                .priorityRequestLow: false, // high priority
            ])
        } else {
            renderingContext = CIContext(options: [
                .cacheIntermediates: true,
                .useSoftwareRenderer: false,
            ])
        }

        processingQueue = DispatchQueue(label: "com.day1-labs.yoyo.movie.filter", qos: .userInitiated)
    }

    // MARK: - Public Methods

    /// moviefilter
    /// - Parameters:
    ///   - sourceMovieURL: movieURL
    ///   - filter: filter
    ///   - destinationURL: URL(can)
    ///   - orientation: capturedeviceorientation
    ///   - assetIdentifier: Live Photo
    ///   - stillImageTime: Live Photo image
    ///   - removeAudio: whetherremoveaudio
    /// - Returns: movieURL, failedoriginalURL
    func applyFilterToMovie(
        sourceURL sourceMovieURL: URL,
        filter: FilterIdentifier,
        destinationURL: URL? = nil,
        orientation: UIDeviceOrientation? = nil,
        assetIdentifier: String? = nil,
        stillImageTime: CMTime? = nil,
        removeAudio: Bool = false
    ) async -> URL? {
        await withTaskGroup(of: URL?.self) { group in
            group.addTask(priority: .userInitiated) { [weak self] in
                guard let self else { return sourceMovieURL }

                return await withCheckedContinuation { continuation in
                    self.processingQueue.async {
                        autoreleasepool {
                            let result = self.processMovieWithFilter(
                                sourceURL: sourceMovieURL,
                                filter: filter,
                                destinationURL: destinationURL,
                                orientation: orientation,
                                assetIdentifier: assetIdentifier,
                                stillImageTime: stillImageTime,
                                removeAudio: removeAudio
                            )
                            continuation.resume(returning: result)
                        }
                    }
                }
            }

            for await result in group {
                return result
            }
            return sourceMovieURL
        }
    }

    // MARK: - Private Methods

    private func processMovieWithFilter(
        sourceURL: URL,
        filter: FilterIdentifier,
        destinationURL: URL?,
        orientation: UIDeviceOrientation?,
        assetIdentifier: String?,
        stillImageTime: CMTime?,
        removeAudio: Bool
    ) -> URL? {
        PerformanceMonitor.shared.measureSync("Movie_Filter_\(filter.displayName)") {
            let sourceAsset = AVURLAsset(url: sourceURL)
            let outputURL = destinationURL ?? FileManager.createTempMovieURL(prefix: "FILTERED_MOVIE")

            guard let videoTrack = sourceAsset.tracks(withMediaType: .video).first else {
                return sourceURL
            }

            return processMovieInternal(
                sourceAsset: sourceAsset,
                videoTrack: videoTrack,
                outputURL: outputURL,
                sourceURL: sourceURL,
                orientation: orientation,
                assetIdentifier: assetIdentifier,
                stillImageTime: stillImageTime,
                filter: filter,
                removeAudio: removeAudio
            )
        }
    }

    private func processMovieInternal(
        sourceAsset: AVURLAsset,
        videoTrack: AVAssetTrack,
        outputURL: URL,
        sourceURL: URL,
        orientation: UIDeviceOrientation?,
        assetIdentifier: String?,
        stillImageTime: CMTime?,
        filter: FilterIdentifier,
        removeAudio: Bool
    ) -> URL? {
        do {
            let assetReader = try AVAssetReader(asset: sourceAsset)
            let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            // if assetIdentifier, Live Photo data
            var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
            if let assetIdentifier {
                let assetIdentifierMetadata = metadataForAssetID(assetIdentifier)
                assetWriter.metadata = [assetIdentifierMetadata]
                metadataAdaptor = createMetadataAdaptorForStillImageTime()
                assetWriter.add(metadataAdaptor!.assetWriterInput)
            }

            // configurevideo
            let pixelBufferAdaptor = configureVideoProcessingPipeline(
                assetReader: assetReader,
                assetWriter: assetWriter,
                videoTrack: videoTrack,
                sourceAsset: sourceAsset,
                orientation: orientation,
                removeAudio: removeAudio
            )

            guard let pixelBufferAdaptor else {
                FileManager.safeRemoveItem(at: outputURL)
                return sourceURL
            }

            guard assetReader.startReading(), assetWriter.startWriting() else {
                FileManager.safeRemoveItem(at: outputURL)
                return sourceURL
            }

            assetWriter.startSession(atSourceTime: .zero)

            // Still Image Time data(Live Photo need to)
            if let adaptor = metadataAdaptor {
                let item = metadataItemForStillImageTime()
                let startTime: CMTime = stillImageTime ?? .zero
                let duration: CMTime
                if videoTrack.nominalFrameRate > 0 {
                    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(videoTrack.nominalFrameRate))
                    duration = frameDuration
                } else {
                    duration = CMTime(value: 1, timescale: 100)
                }
                let timeRange = CMTimeRange(start: startTime, duration: duration)
                let metadataGroup = AVTimedMetadataGroup(items: [item], timeRange: timeRange)
                adaptor.append(metadataGroup)
            }

            // video
            let processingConfig = filterManager.getProcessingConfig(for: filter) ?? FilterProcessingConfig(processingType: .builtin)
            let intensity = filterManager.getIntensity(for: filter)
            let processingSuccess = executeFrameProcessing(
                reader: assetReader,
                writer: assetWriter,
                pixelBufferAdaptor: pixelBufferAdaptor,
                processingConfig: processingConfig,
                intensity: intensity
            )

            guard processingSuccess else {
                FileManager.safeRemoveItem(at: outputURL)
                return sourceURL
            }

            return validateProcessedMovie(outputURL: outputURL, originalURL: sourceURL)

        } catch {
            FileManager.safeRemoveItem(at: outputURL)
            return sourceURL
        }
    }

    /// configurevideo
    private func configureVideoProcessingPipeline(
        assetReader: AVAssetReader,
        assetWriter: AVAssetWriter,
        videoTrack: AVAssetTrack,
        sourceAsset: AVURLAsset,
        orientation: UIDeviceOrientation?,
        removeAudio: Bool
    ) -> AVAssetWriterInputPixelBufferAdaptor? {
        // configurevideooutput
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            ]
        )
        assetReader.add(videoReaderOutput)

        // configurevideoinput
        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: videoTrack.naturalSize.width,
            AVVideoHeightKey: videoTrack.naturalSize.height,
        ]

        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        // Transform
        if let orientation {
            switch orientation {
            case .portrait:
                videoWriterInput.transform = CGAffineTransform(rotationAngle: .pi / 2)
            case .portraitUpsideDown:
                videoWriterInput.transform = CGAffineTransform(rotationAngle: -.pi / 2)
            case .landscapeRight:
                videoWriterInput.transform = CGAffineTransform(rotationAngle: .pi)
            case .landscapeLeft:
                videoWriterInput.transform = .identity
            @unknown default:
                videoWriterInput.transform = CGAffineTransform(rotationAngle: .pi / 2)
            }

        } else {
            videoWriterInput.transform = CGAffineTransform(rotationAngle: .pi / 2)
        }

        videoWriterInput.expectsMediaDataInRealTime = false

        // createpixel buffer adaptor(startWriting)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            ]
        )

        assetWriter.add(videoWriterInput)

        // configureaudio
        if !removeAudio {
            configureAudioProcessingPipeline(
                sourceAsset: sourceAsset,
                assetReader: assetReader,
                assetWriter: assetWriter
            )
        }

        return pixelBufferAdaptor
    }

    private func configureAudioProcessingPipeline(
        sourceAsset: AVURLAsset,
        assetReader: AVAssetReader,
        assetWriter: AVAssetWriter
    ) {
        guard let audioTrack = sourceAsset.tracks(withMediaType: .audio).first else {
            return
        }

        let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        assetReader.add(audioReaderOutput)

        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        audioWriterInput.expectsMediaDataInRealTime = false
        assetWriter.add(audioWriterInput)
    }

    /// video
    private func executeFrameProcessing(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        processingConfig: FilterProcessingConfig,
        intensity: Float
    ) -> Bool {
        let processor = ParallelFrameProcessor(
            reader: reader,
            writer: writer,
            pixelBufferAdaptor: pixelBufferAdaptor,
            renderingContext: renderingContext,
            processingConfig: processingConfig,
            intensity: intensity
        )
        return processor.start()
    }

    // MARK: - Parallel Frame Processor

    private final class ParallelFrameProcessor {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
        let renderingContext: CIContext
        let processingConfig: FilterProcessingConfig
        let intensity: Float

        // Concurrency control - use 6 parallel A
        let maxConcurrent = 6
        let processingQueue = DispatchQueue(label: "com.day1-labs.yoyo.movie.processing", attributes: .concurrent)
        let producerQueue = DispatchQueue(label: "com.day1-labs.yoyo.movie.producer", qos: .userInitiated)
        let backpressureSemaphore: DispatchSemaphore

        // State
        var nextReadIndex = 0
        var nextWriteIndex = 0
        var processedFrames: [Int: (CVPixelBuffer, CMTime)] = [:]
        var processingError: Error?
        var isReadingFinished = false

        /// Synchronization
        let stateLock = NSCondition()

        init(
            reader: AVAssetReader,
            writer: AVAssetWriter,
            pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
            renderingContext: CIContext,
            processingConfig: FilterProcessingConfig,
            intensity: Float
        ) {
            self.reader = reader
            self.writer = writer
            self.pixelBufferAdaptor = pixelBufferAdaptor
            self.renderingContext = renderingContext
            self.processingConfig = processingConfig
            self.intensity = intensity
            backpressureSemaphore = DispatchSemaphore(value: maxConcurrent)
        }

        func start() -> Bool {
            guard let videoReaderOutput = reader.outputs.first(where: { $0.mediaType == .video }) as? AVAssetReaderTrackOutput,
                  let videoWriterInput = writer.inputs.first(where: { $0.mediaType == .video })
            else {
                return false
            }

            let audioReaderOutput = reader.outputs.first(where: { $0.mediaType == .audio }) as? AVAssetReaderTrackOutput
            let audioWriterInput = writer.inputs.first(where: { $0.mediaType == .audio })

            // Start Producer
            producerQueue.async {
                self.producerLoop(videoReaderOutput: videoReaderOutput)
            }

            let processingGroup = DispatchGroup()
            var videoSuccess = false
            var audioSuccess = audioReaderOutput == nil || audioWriterInput == nil

            // Setup Video Consumer
            let videoQueue = DispatchQueue(label: "movieFilterProcessing", qos: .userInitiated)
            processingGroup.enter()
            videoWriterInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
                guard let self else { return }

                while videoWriterInput.isReadyForMoreMediaData {
                    if let (pixelBuffer, presentationTime) = self.waitForNextFrame() {
                        if !self.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                            self.setError(NSError(domain: "MovieFilterProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to append pixel buffer"]))
                            videoWriterInput.markAsFinished()
                            videoSuccess = false
                            processingGroup.leave()
                            return
                        }
                    } else {
                        // No more frames or error
                        videoWriterInput.markAsFinished()
                        videoSuccess = self.processingError == nil
                        processingGroup.leave()
                        return
                    }
                }
            }

            // Setup Audio Consumer (Pass-through)
            if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
                let audioQueue = DispatchQueue(label: "audioProcessing", qos: .userInitiated)
                processingGroup.enter()
                audioInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioInput.isReadyForMoreMediaData {
                        guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            audioSuccess = true
                            processingGroup.leave()
                            return
                        }
                        audioInput.append(sampleBuffer)
                    }
                }
            }

            // Wait for all processing to complete
            processingGroup.wait()

            // Check reader/writer status
            if reader.status == .failed {
                return false
            }

            // Finish writing
            let finishSemaphore = DispatchSemaphore(value: 0)
            var writeSuccess = false

            writer.finishWriting {
                writeSuccess = self.writer.status == .completed
                finishSemaphore.signal()
            }
            finishSemaphore.wait()

            return videoSuccess && writeSuccess
        }

        private func producerLoop(videoReaderOutput: AVAssetReaderTrackOutput) {
            while let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                backpressureSemaphore.wait()

                let index = nextReadIndex
                nextReadIndex += 1

                processingQueue.async {
                    self.processFrame(sampleBuffer: sampleBuffer, index: index)
                }
            }

            stateLock.lock()
            isReadingFinished = true
            stateLock.signal()
            stateLock.unlock()
        }

        private func processFrame(sampleBuffer: CMSampleBuffer, index: Int) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                signalError(NSError(domain: "MovieFilterProcessor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel buffer"]))
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // Apply Filter
            var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            // use frameSeed, ensurevideo
            let frameSeed = UInt32(index)
            ciImage = FilterManager.shared.applyFilter(to: ciImage, processingConfig: processingConfig, intensity: intensity, frameSeed: frameSeed, quality: .full)

            // Get Output Buffer
            guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
                signalError(NSError(domain: "MovieFilterProcessor", code: -3, userInfo: [NSLocalizedDescriptionKey: "Pixel buffer pool is nil"]))
                return
            }

            var outputPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputPixelBuffer)

            guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
                signalError(NSError(domain: "MovieFilterProcessor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output pixel buffer"]))
                return
            }

            // Render
            renderingContext.render(ciImage, to: outputBuffer)

            // Store Result
            stateLock.lock()
            processedFrames[index] = (outputBuffer, presentationTime)
            stateLock.signal()
            stateLock.unlock()
        }

        private func waitForNextFrame() -> (CVPixelBuffer, CMTime)? {
            stateLock.lock()
            defer { stateLock.unlock() }

            while processedFrames[nextWriteIndex] == nil {
                if processingError != nil { return nil }
                if isReadingFinished, nextWriteIndex == nextReadIndex { return nil }

                stateLock.wait()
            }

            let result = processedFrames[nextWriteIndex]
            processedFrames.removeValue(forKey: nextWriteIndex)
            nextWriteIndex += 1
            backpressureSemaphore.signal()
            return result
        }

        private func signalError(_ error: Error) {
            stateLock.lock()
            processingError = error
            stateLock.signal()
            stateLock.unlock()
            backpressureSemaphore.signal() // Release to avoid deadlock
        }

        private func setError(_ error: Error) {
            stateLock.lock()
            processingError = error
            stateLock.signal()
            stateLock.unlock()
        }
    }

    private func validateProcessedMovie(outputURL: URL, originalURL: URL) -> URL? {
        // check
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            print("❌ [MovieFilter] Output file does not exist")
            return originalURL
        }

        // check - usepropertiesnot
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            if fileSize < 1024 {
                print("❌ [MovieFilter] Output file too small: \(fileSize) bytes")
                FileManager.safeRemoveItem(at: outputURL)
                return originalURL
            }
        } catch {
            print("❌ [MovieFilter] Failed to get file attributes: \(error)")
            return originalURL
        }

        // remove AVURLAsset validate - AVAssetWriter result
        return outputURL
    }

    // MARK: - LivePhoto Metadata Helpers

    private func metadataForAssetID(_ assetIdentifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        let keyContentIdentifier = "com.apple.quicktime.content.identifier"
        let keySpaceQuickTimeMetadata = "mdta"
        item.key = keyContentIdentifier as (NSCopying & NSObjectProtocol)?
        item.keySpace = AVMetadataKeySpace(rawValue: keySpaceQuickTimeMetadata)
        item.value = assetIdentifier as (NSCopying & NSObjectProtocol)?
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        return item
    }

    private func createMetadataAdaptorForStillImageTime() -> AVAssetWriterInputMetadataAdaptor {
        let keyStillImageTime = "com.apple.quicktime.still-image-time"
        let keySpaceQuickTimeMetadata = "mdta"
        let spec: NSDictionary = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as NSString:
                "\(keySpaceQuickTimeMetadata)/\(keyStillImageTime)",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as NSString:
                "com.apple.metadata.datatype.int8",
        ]
        var desc: CMFormatDescription? = nil
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &desc)
        let input = AVAssetWriterInput(mediaType: .metadata,
                                       outputSettings: nil, sourceFormatHint: desc)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }

    private func metadataItemForStillImageTime() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        let keyStillImageTime = "com.apple.quicktime.still-image-time"
        let keySpaceQuickTimeMetadata = "mdta"
        item.key = keyStillImageTime as (NSCopying & NSObjectProtocol)?
        item.keySpace = AVMetadataKeySpace(rawValue: keySpaceQuickTimeMetadata)
        item.value = 0 as (NSCopying & NSObjectProtocol)?
        item.dataType = "com.apple.metadata.datatype.int8"
        return item
    }
}
