import AVFoundation
import CoreImage
import Photos
import UIKit

actor VideoGenerator {
    static let shared = VideoGenerator()

    enum GeneratorError: Error {
        case noAssets
        case outputCreationFailed
        case writerSetupFailed
        case cancelled
        case unknown
    }

    private let ciContext = CIContext()

    private struct Segment {
        let startTime: CMTime
        let duration: CMTime
        let sourceAsset: AVAsset?
    }

    func generateVideo(from assets: [PHAsset], progress: ((Double) -> Void)? = nil) async throws -> URL {
        guard !assets.isEmpty else { throw GeneratorError.noAssets }

        // Default to 1080p Portrait (9:16)
        let outputSize = CGSize(width: 1080, height: 1920)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
        ]

        let filename = "generated_video_\(Date().timeIntervalSince1970).mov"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height,
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: bufferAttributes)

        guard assetWriter.canAdd(writerInput) else { throw GeneratorError.writerSetupFailed }
        assetWriter.add(writerInput)

        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)

        var currentFrameTime = CMTime.zero
        let frameDuration = CMTime(value: 1, timescale: 30) // 30fps
        let photoDuration = CMTime(value: 2, timescale: 1) // 2 seconds per photo

        var segments: [Segment] = []

        let totalCount = Double(assets.count)

        for (index, asset) in assets.enumerated() {
            // Check for cancellation or errors? (Not easily doable in this loop structure without checking a flag)

            if asset.mediaType == .image {
                let segmentStart = currentFrameTime
                if let image = await fetchImage(for: asset, targetSize: outputSize),
                   let buffer = pixelBuffer(from: image, size: outputSize, pool: adaptor.pixelBufferPool)
                {
                    let numberOfFrames = Int(photoDuration.seconds * 30)
                    for _ in 0 ..< numberOfFrames {
                        while !writerInput.isReadyForMoreMediaData {
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }

                        autoreleasepool {
                            adaptor.append(buffer, withPresentationTime: currentFrameTime)
                        }
                        currentFrameTime = currentFrameTime + frameDuration
                    }
                }

                segments.append(Segment(startTime: segmentStart, duration: photoDuration, sourceAsset: nil))
                let imageTargetEnd = segmentStart + photoDuration
                if currentFrameTime < imageTargetEnd {
                    currentFrameTime = imageTargetEnd
                }
            } else if asset.mediaType == .video {
                let segmentStart = currentFrameTime
                if let avAsset = await fetchAVAsset(for: asset) {
                    let duration = await (try? avAsset.load(.duration)) ?? CMTime(seconds: asset.duration, preferredTimescale: 600)
                    try await appendVideo(
                        asset: avAsset,
                        to: adaptor,
                        writerInput: writerInput,
                        segmentStartTime: segmentStart,
                        outputSize: outputSize
                    )

                    segments.append(Segment(startTime: segmentStart, duration: duration, sourceAsset: avAsset))

                    let videoTargetEnd = segmentStart + duration
                    let targetEndWithPad = videoTargetEnd + frameDuration
                    if currentFrameTime < targetEndWithPad {
                        currentFrameTime = targetEndWithPad
                    }
                }
            }

            progress?(Double(index + 1) / totalCount)
        }

        writerInput.markAsFinished()
        await assetWriter.finishWriting()

        let finalURL = try await muxAudioIfNeeded(videoURL: outputURL, segments: segments)
        if finalURL != outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }

        return finalURL
    }

    private func fetchImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func fetchAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    private func pixelBuffer(from image: UIImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        var status: CVReturn

        if let pool {
            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        } else {
            status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        }

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(data: pixelData, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }

        // Flip context to match UIKit coordinate system
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)

        // Draw aspect fill
        let widthRatio = size.width / image.size.width
        let heightRatio = size.height / image.size.height
        let scaleFactor = max(widthRatio, heightRatio)

        let scaledWidth = image.size.width * scaleFactor
        let scaledHeight = image.size.height * scaleFactor
        let imageX = (size.width - scaledWidth) / 2
        let imageY = (size.height - scaledHeight) / 2

        image.draw(in: CGRect(x: imageX, y: imageY, width: scaledWidth, height: scaledHeight))
        UIGraphicsPopContext()

        return buffer
    }

    private func appendVideo(
        asset: AVAsset,
        to adaptor: AVAssetWriterInputPixelBufferAdaptor,
        writerInput: AVAssetWriterInput,
        segmentStartTime: CMTime,
        outputSize: CGSize
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }

        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        ]

        let videoComposition = AVVideoComposition(propertiesOf: asset)
        let readerOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: readerOutputSettings)
        readerOutput.videoComposition = videoComposition
        readerOutput.alwaysCopiesSampleData = false

        if reader.canAdd(readerOutput) {
            reader.add(readerOutput)
        } else {
            return
        }

        reader.startReading()

        var firstPTS: CMTime?
        var lastPresentationTime = segmentStartTime

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            autoreleasepool {
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let ciImage = CIImage(cvPixelBuffer: imageBuffer)

                    // Calculate scale to aspect fill outputSize
                    let bufferWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
                    let bufferHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))

                    let scaleX = outputSize.width / bufferWidth
                    let scaleY = outputSize.height / bufferHeight
                    let scale = max(scaleX, scaleY)

                    // Apply transform
                    var transformedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

                    // Center crop
                    let x = (transformedImage.extent.width - outputSize.width) / 2
                    let y = (transformedImage.extent.height - outputSize.height) / 2

                    // We need to clamp x/y to be safe
                    let cropRect = CGRect(x: x, y: y, width: outputSize.width, height: outputSize.height)
                    transformedImage = transformedImage.cropped(to: cropRect)

                    // Move back to origin (0,0) for rendering
                    transformedImage = transformedImage.transformed(by: CGAffineTransform(translationX: -transformedImage.extent.origin.x, y: -transformedImage.extent.origin.y))

                    var newPixelBuffer: CVPixelBuffer?
                    var status: CVReturn

                    if let pool = adaptor.pixelBufferPool {
                        status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &newPixelBuffer)
                    } else {
                        status = CVPixelBufferCreate(nil, Int(outputSize.width), Int(outputSize.height), kCVPixelFormatType_32ARGB, nil, &newPixelBuffer)
                    }

                    if status == kCVReturnSuccess, let newBuffer = newPixelBuffer {
                        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        if firstPTS == nil {
                            firstPTS = pts
                        }
                        let relativePTS = pts - (firstPTS ?? .zero)
                        let presentationTime = segmentStartTime + relativePTS
                        ciContext.render(transformedImage, to: newBuffer)
                        adaptor.append(newBuffer, withPresentationTime: presentationTime)
                        lastPresentationTime = presentationTime
                    }
                }
            }
        }

        reader.cancelReading()
    }

    private func muxAudioIfNeeded(videoURL: URL, segments: [Segment]) async throws -> URL {
        var needsAudio = false
        for segment in segments {
            guard let asset = segment.sourceAsset else { continue }
            if let hasAudio = try? await asset.loadTracks(withMediaType: .audio).isEmpty == false, hasAudio {
                needsAudio = true
                break
            }
        }

        guard needsAudio else { return videoURL }

        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoURL)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            return videoURL
        }

        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return videoURL
        }

        let videoDuration = await (try? videoAsset.load(.duration)) ?? .zero
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero)

        let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        if let compositionAudioTrack {
            for segment in segments {
                guard let sourceAsset = segment.sourceAsset else { continue }
                guard let sourceAudioTrack = try? await sourceAsset.loadTracks(withMediaType: .audio).first else { continue }

                let sourceDuration = await (try? sourceAsset.load(.duration)) ?? segment.duration
                let duration = min(sourceDuration, segment.duration)
                guard duration > .zero else { continue }

                do {
                    try compositionAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: sourceAudioTrack,
                        at: segment.startTime
                    )
                } catch {
                    continue
                }
            }
        }

        let filename = "generated_video_with_audio_\(Date().timeIntervalSince1970).mov"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return videoURL
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? GeneratorError.unknown)
                case .cancelled:
                    continuation.resume(throwing: GeneratorError.cancelled)
                default:
                    continuation.resume(throwing: exportSession.error ?? GeneratorError.unknown)
                }
            }
        }

        return outputURL
    }
}
