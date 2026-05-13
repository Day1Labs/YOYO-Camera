import CoreImage
import SwiftData
import SwiftUI
import Vision

/*
 * AestheticsScoreManager - A manager for aesthetic score computation
 *
 * Features:
 * 1. Delays aesthetic score computation to avoid blocking the capture flow
 * 2. Uses batch processing to reduce system resource usage
 * 3. Manages an intelligent queue to avoid duplicate computation
 * 4. Pauses computation in the background with app lifecycle awareness
 * 5. Supports manual control and error handling
 */

/// Aesthetic score manager responsible for delayed and batched processing.
@MainActor
final class AestheticsScoreManager: ObservableObject {
    static let shared = AestheticsScoreManager()

    /// Photo queue waiting for scoring.
    private var pendingPhotos: [PhotoAsset] = []

    // Calculation status.
    @Published var isCalculating = false
    @Published var pendingCount = 0

    // Batch processing configuration.
    private let batchSize = 3 // Process 3 photos at a time.
    private let delayInterval: TimeInterval = 5.0 // Delay 5 seconds to start calculation.
    private let batchInterval: TimeInterval = 2.0 // Batch interval 2 seconds.
    // Timer.
    private var delayTimer: Timer?
    private var batchTimer: Timer?

    init() {
        // Start the delayed calculation mechanism.
        startDelayedCalculation()
    }

    deinit {
        delayTimer?.invalidate()
        batchTimer?.invalidate()
    }

    /// Add a photo that should be scored later.
    func addPhotoForScoreCalculation(_ photo: PhotoAsset) {
        // Skip photos that already have a score.
        if photo.aestheticsScore != nil {
            return
        }

        // Add to the pending queue.
        pendingPhotos.append(photo)
        pendingCount = pendingPhotos.count

        // Start the delay timer if needed.
        if delayTimer == nil, !isCalculating {
            startDelayedCalculation()
        }
    }

    /// Start the delayed calculation mechanism.
    private func startDelayedCalculation() {
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: delayInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startBatchCalculation()
            }
        }
    }

    /// Start batched calculation.
    private func startBatchCalculation() {
        guard !pendingPhotos.isEmpty, !isCalculating else { return }

        isCalculating = true

        Task.detached(priority: .background) { [weak self] in
            await self?.processBatch()
        }
    }

    /// Process a batch of queued photos.
    private func processBatch() async {
        await MainActor.run {
            guard !pendingPhotos.isEmpty else {
                isCalculating = false
                return
            }

            // Get the current batch.
            let currentBatch = Array(pendingPhotos.prefix(batchSize))
            pendingPhotos.removeFirst(min(batchSize, pendingPhotos.count))
            pendingCount = pendingPhotos.count

            // Calculate ratings on a background thread.
            Task.detached(priority: .background) { [weak self] in
                await self?.calculateScoresForBatch(currentBatch)
            }
        }
    }

    /// Calculate scores for a batch of photos.
    private func calculateScoresForBatch(_ photos: [PhotoAsset]) async {
        for photo in photos {
            await calculateScoreForPhoto(photo)

            // Pause briefly between photos to reduce resource pressure.
            try? await Task.sleep(nanoseconds: UInt64(batchInterval * 1_000_000_000))
        }

        // Check whether more photos remain pending.
        await MainActor.run {
            if !pendingPhotos.isEmpty {
                // Continue with the next batch.
                Task.detached(priority: .background) { [weak self] in
                    await self?.processBatch()
                }
            } else {
                isCalculating = false
            }
        }
    }

    /// Calculate a score for a single photo.
    private func calculateScoreForPhoto(_ photo: PhotoAsset) async {
        // Double-check that the photo does not already have a score.
        await MainActor.run {
            if photo.aestheticsScore != nil {
                return
            }
        }

        guard let image = await photo.loadFullImage() else { return }

        do {
            if #available(iOS 18.0, *) {
                let score = try await calculateAestheticsScoreForImage(image)

                // Save the score to the model.
                await MainActor.run {
                    photo.aestheticsScore = score
                    do {
                        try photo.modelContext?.save()
                        print("图片美学评分计算完成: \(score)")
                    } catch {
                        print("保存美学评分失败: \(error)")
                    }
                }
            }
        } catch {
            print("计算图片美学评分失败: \(error.localizedDescription)")
        }
    }

    @available(iOS 18.0, *)
    private func calculateAestheticsScoreForImage(_ image: UIImage) async throws -> Float {
        try await Self.calculateAestheticsScore(for: image)
    }

    /// Calculate the aesthetic score for a single image.
    @available(iOS 18.0, *)
    static func calculateAestheticsScore(for image: UIImage) async throws -> Float {
        // 1. Convert to `CIImage`.
        guard let ciimage = CIImage(image: image) else {
            throw NSError(domain: "AestheticsScoreError", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建CIImage"])
        }

        // 2. Set up the rating request.
        let request = Vision.CalculateImageAestheticsScoresRequest()

        // 3. Execute the request.
        let observation = try await request.perform(on: ciimage)

        // 4. Use the overall rating (range 0-10).
        return observation.overallScore * 10
    }

    /// Calculate and save an aesthetic score for a single photo.
    @available(iOS 18.0, *)
    @MainActor
    static func calculateAndSaveScore(for photo: PhotoAsset) async throws -> Float {
        // If a score already exists, return it directly.
        if let existingScore = photo.aestheticsScore {
            return existingScore
        }

        // Load the image.
        guard let image = await photo.loadFullImage() else {
            throw NSError(domain: "AestheticsScoreError", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法加载图片"])
        }

        // Calculate the score.
        let score = try await calculateAestheticsScore(for: image)

        // Save to the model.
        photo.aestheticsScore = score
        do {
            try photo.modelContext?.save()
            print("图片美学评分计算完成: \(score)")
        } catch {
            print("保存美学评分失败: \(error)")
            throw error
        }

        return score
    }

    /// Manually trigger calculation.
    func triggerCalculation() {
        delayTimer?.invalidate()
        delayTimer = nil
        startBatchCalculation()
    }

    /// Clear the pending queue.
    func clearPendingQueue() {
        pendingPhotos.removeAll()
        pendingCount = 0
        isCalculating = false
        delayTimer?.invalidate()
        delayTimer = nil
    }

    /// Pause aesthetic score calculation.
    @available(*, deprecated, message: "The aesthetic score has been changed to be calculated on demand, and the pause/resume mechanism is no longer needed")
    func pauseCalculation() {
        delayTimer?.invalidate()
        batchTimer?.invalidate()
        isCalculating = false
    }

    /// Resume aesthetic score calculation.
    @available(*, deprecated, message: "The aesthetic score has been changed to be calculated on demand, and the pause/resume mechanism is no longer needed")
    func resumeCalculation() {
        // Continue processing if pending photos still exist.
        if !pendingPhotos.isEmpty {
            startBatchCalculation()
        } else {
            // Otherwise restart the delayed calculation timer.
            startDelayedCalculation()
        }
    }
}

// MARK: - Test extension
#if DEBUG
    extension AestheticsScoreManager {
        /// Test method: get current configuration information.
        func getConfigurationInfo() -> [String: Any] {
            [
                "batchSize": batchSize,
                "delayInterval": delayInterval,
                "batchInterval": batchInterval,
                "pendingCount": pendingCount,
                "isCalculating": isCalculating,
            ]
        }

        /// Test method: simulate adding a test photo.
        func addTestPhoto() {
            // Create a mock photo object for testing.
            let testPhoto = PhotoAsset(
                previewAssetIdentifier: "test_asset_\(UUID().uuidString)",
                title: "Test Photo"
            )
            addPhotoForScoreCalculation(testPhoto)
        }
    }
#endif
