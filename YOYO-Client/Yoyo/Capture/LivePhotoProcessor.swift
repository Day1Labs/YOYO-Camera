import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import UIKit

/// Live Photo processor - Live Photo (image+video+statemanagement)
actor LivePhotoProcessor {
    static let shared = LivePhotoProcessor()

    // Shared components
    private let movieFilterProcessor: MovieFilterProcessor
    private let metadataBuilder = MetadataBuilder.shared

    // MARK: - LivePhoto State Management

    /// Live Photostate
    private struct LivePhotoCapture {
        let uniqueID: Int
        var assetIdentifier: String
        var filteredImage: UIImage?
        var originalImage: UIImage?
        var originalImageData: Data?
        var metadata: [String: Any]?
        var videoURL: URL?
        var processedVideoURL: URL? // videoURL
        var videoProcessingTask: Task<URL?, Never>? // video
        let timestamp: Date
        let orientation: UIDeviceOrientation // capturedeviceorientation
        var isFinishing: Bool = false // whetherin progresscomplete, clean up
    }

    private var activeCaptures: [Int: LivePhotoCapture] = [:]
    private let captureTimeout: TimeInterval = 30.0

    // MARK: - Initialization

    private init() {
        // initializationshared components
        movieFilterProcessor = MovieFilterProcessor()
    }

    // MARK: - Public Methods

    /// startLive Photo, createstate
    func beginCapture(uniqueID: Int, orientation: UIDeviceOrientation) {
        let assetIdentifier = UUID().uuidString
        let capture = LivePhotoCapture(
            uniqueID: uniqueID,
            assetIdentifier: assetIdentifier,
            timestamp: Date(),
            orientation: orientation
        )
        activeCaptures[uniqueID] = capture
        print("🎬 [LivePhoto] Begin capture - uniqueID: \(uniqueID)")

        // setclean up
        Task { [weak self] in
            let timeout = self?.captureTimeout ?? 30.0
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await self?.timeoutCleanup(uniqueID: uniqueID)
        }
    }

    /// savevideoURLandstartasync(didFinishProcessingLive Photocallback)
    /// - Parameters:
    ///   - uniqueID: capture
    ///   - videoURL: videoURL
    ///   - filter: filter
    ///   - photoDisplayTime: image
    ///   - isMuted: whether
    func saveVideoURL(uniqueID: Int, videoURL: URL, filter: FilterIdentifier?, photoDisplayTime: CMTime? = nil, isMuted: Bool = false) {
        guard var capture = activeCaptures[uniqueID] else {
            return
        }

        capture.videoURL = videoURL
        let orientation = capture.orientation
        let assetIdentifier = capture.assetIdentifier

        // video(origin filter), and Live Photo metadata
        let effectiveFilter = filter ?? .none
        let task = Task(priority: .userInitiated) {
            await self.movieFilterProcessor.applyFilterToMovie(
                sourceURL: videoURL,
                filter: effectiveFilter,
                orientation: orientation,
                assetIdentifier: assetIdentifier,
                stillImageTime: photoDisplayTime,
                removeAudio: isMuted
            )
        }
        capture.videoProcessingTask = task
        activeCaptures[uniqueID] = capture
    }

    /// completeLive Photoandresult(waitvideocomplete)
    func finishCapture(uniqueID: Int) async -> CaptureResult? {
        // waitimagedataprepare(wait 10)
        let maxWaitTime: TimeInterval = 10.0
        let checkInterval: UInt64 = 100_000_000 // 100ms
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < maxWaitTime {
            guard let capture = activeCaptures[uniqueID] else {
                print("❌ [LivePhoto] Finish failed - capture not found for uniqueID: \(uniqueID)")
                return nil
            }

            // checkimagedatawhetherprepare
            if capture.filteredImage != nil, capture.originalImage != nil {
                break
            }

            // wait
            try? await Task.sleep(nanoseconds: checkInterval)
        }

        guard var capture = activeCaptures[uniqueID] else {
            print("❌ [LivePhoto] Finish failed - capture not found for uniqueID: \(uniqueID)")
            return nil
        }

        guard let filteredImage = capture.filteredImage,
              let originalImage = capture.originalImage
        else {
            print("❌ [LivePhoto] Finish failed - image data not ready after waiting for uniqueID: \(uniqueID)")
            return nil
        }

        // in progresscomplete, clean up
        capture.isFinishing = true
        activeCaptures[uniqueID] = capture

        print("🎬 [LivePhoto] Starting video processing wait for uniqueID: \(uniqueID)")

        // ⚡️ waitvideocomplete
        let processedVideoURL: URL? = await {
            if let task = capture.videoProcessingTask {
                return await task.value
            } else if let url = capture.processedVideoURL {
                return url
            } else if let url = capture.videoURL {
                return url
            } else {
                return nil
            }
        }()

        // data
        var metadata = metadataBuilder.buildLivePhotoMetadata(
            uniqueID: uniqueID,
            originalMetadata: capture.metadata
        )
        metadata["livePhotoAssetIdentifier"] = capture.assetIdentifier

        guard let videoURL = processedVideoURL else {
            print("❌ [LivePhoto] Finish failed - no video URL")
            return nil
        }

        // clean upstate
        activeCaptures.removeValue(forKey: uniqueID)
        print("✅ [LivePhoto] Finish capture - uniqueID: \(uniqueID)")

        return CaptureResult(
            originalImage: originalImage,
            filteredImage: filteredImage,
            metadata: metadata,
            livePhotoURL: videoURL,
            originalImageData: capture.originalImageData,
            originalVideoURL: capture.videoURL
        )
    }

    /// Live Photo
    func cancelCapture(uniqueID: Int) {
        activeCaptures.removeValue(forKey: uniqueID)
    }

    /// checkwhether
    func hasActiveCapture(uniqueID: Int) -> Bool {
        activeCaptures[uniqueID] != nil
    }

    /// saveimagedata(CameraCaptureService)
    func saveImageData(
        uniqueID: Int,
        filteredImage: UIImage,
        originalImage: UIImage,
        originalImageData: Data?,
        metadata: [String: Any]?
    ) {
        guard var capture = activeCaptures[uniqueID] else {
            return
        }

        capture.filteredImage = filteredImage
        capture.originalImage = originalImage
        capture.originalImageData = originalImageData
        capture.metadata = metadata
        activeCaptures[uniqueID] = capture
    }

    // MARK: - Private Methods

    /// clean up
    private func timeoutCleanup(uniqueID: Int) {
        if let capture = activeCaptures[uniqueID] {
            // ifin progresscomplete, not clean up
            if capture.isFinishing {
                print("⏳ [LivePhoto] Timeout skipped - finishing in progress for uniqueID: \(uniqueID)")
                return
            }

            let elapsed = Date().timeIntervalSince(capture.timestamp)
            if elapsed >= captureTimeout {
                activeCaptures.removeValue(forKey: uniqueID)
                print("⚠️ [LivePhoto] Timeout cleanup - uniqueID: \(uniqueID), elapsed: \(String(format: "%.1f", elapsed))s")
            }
        }
    }
}
