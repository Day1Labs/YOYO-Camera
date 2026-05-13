import AVFoundation
import CoreLocation
import Foundation
import Photos
import SwiftData
import SwiftUI

/// camerasave - photovideosavelogic
final class CameraSaveService {
    // MARK: - Singleton

    static let shared = CameraSaveService()

    // MARK: - Dependencies

    private var modelContext: ModelContext?

    // MARK: - Initialization

    private init() {}

    /// setdependencies
    func setup(
        modelContext: ModelContext
    ) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// captureresult(CameraView.handleCaptureResult)
    func handleCaptureResult(_ result: CaptureResult?) async {
        guard let result else { return }
        // main thread, actor settingsState
        guard let settingsSnapshot = await currentSaveSettingsSnapshot() else { return }

        // saveoperation, not thencreate Task.detached
        // this way result performSaveOperation can release
        await performSaveOperation(result: result, settings: settingsSnapshot)
    }

    /// Get current memory usage (MB)
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0.0
    }

    /// saveoperation
    /// A: data, CaptureResult
    private func performSaveOperation(result: CaptureResult, settings: SaveSettingsSnapshot) async {
        let startMemory = getMemoryUsage()
        print("💾 [SaveService] Starting save - Memory: \(String(format: "%.1f", startMemory))MB")
        print("💾 [SaveService] CaptureResult size - originalImage: \(result.originalImage.size), filteredImage: \(result.filteredImage.size), originalData: \(result.originalImageData?.count ?? 0) bytes")

        // need to data, let result release
        let isVideo = result.isVideo
        let videoURL = result.videoURL
        let originalVideoURL = result.originalVideoURL
        let metadata = result.metadata
        let filteredImage = result.filteredImage
        let originalImage = result.originalImage
        let originalImageData = result.originalImageData
        let livePhotoURL = result.livePhotoURL

        print("💾 [SaveService] Data extracted from CaptureResult - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        do {
            if isVideo, let videoURL {
                try await saveVideo(videoURL: videoURL, originalVideoURL: originalVideoURL, metadata: metadata, settings: settings)
            } else {
                try await savePhotoWithExtractedData(
                    filteredImage: filteredImage,
                    originalImage: originalImage,
                    originalImageData: originalImageData,
                    livePhotoURL: livePhotoURL,
                    originalVideoURL: originalVideoURL,
                    metadata: metadata,
                    settings: settings,
                    isRaw: result.isRaw
                )
            }

            print("✅ [SaveService] Save completed successfully")
            await notifySaveResult(success: true)
        } catch {
            if !Task.isCancelled {
                print("❌ [SaveService] Save operation failed: \(error.localizedDescription)")
                await handleSaveError(error)
            } else {
                print("⚠️ [SaveService] Save operation cancelled")
                await notifySaveResult(success: false)
            }
        }

        let endMemory = getMemoryUsage()
        print("💾 [SaveService] Save completed - Memory: \(String(format: "%.1f", endMemory))MB (Δ: \(String(format: "%.1f", endMemory - startMemory))MB)")
    }

    /// notifysaveresult
    private func notifySaveResult(success: Bool, error: Error? = nil) async {
        await MainActor.run {
            var userInfo: [AnyHashable: Any] = [CameraNotificationKeys.saveSuccess: success]
            if let error { userInfo[CameraNotificationKeys.saveError] = error }
            NotificationCenter.default.post(
                name: .cameraSaveFinished,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    /// saveerror
    private func handleSaveError(_ error: Error) async {
        await MainActor.run {
            CameraViewState.shared.showError("保存失败: \(error.localizedDescription)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        await notifySaveResult(success: false, error: error)
    }

    // MARK: - Photo Saving

    /// usedatasavephoto
    private func savePhotoWithExtractedData(
        filteredImage: UIImage,
        originalImage: UIImage,
        originalImageData: Data?,
        livePhotoURL: URL?,
        originalVideoURL: URL?,
        metadata: [String: Any]?,
        settings: SaveSettingsSnapshot,
        isRaw: Bool
    ) async throws {
        // data
        let metadataData = try await serializeMetadata(metadata)

        print("💾 [SaveService] Before savePhotoToAlbum - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        // savephoto library
        let (assetIdentifier, originalAssetIdentifier) = try await savePhotoToAlbum(
            image: filteredImage,
            originalImage: originalImage,
            originalImageData: originalImageData,
            livePhotoVideoURL: livePhotoURL,
            originalLivePhotoVideoURL: originalVideoURL,
            metadata: metadata,
            saveOptions: settings,
            isRaw: isRaw
        )

        print("💾 [SaveService] After savePhotoToAlbum - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        // save SwiftData(need to main thread)
        try await MainActor.run { [weak self] in
            guard let self, let modelContext = self.modelContext else { return }
            let photo = PhotoAsset(
                assetIdentifier: assetIdentifier,
                originalAssetIdentifier: originalAssetIdentifier,
                metadata: metadataData,
                filterIdentifier: FilterManager.shared.selectedFilter,
                mediaType: 1, // image
                isLivePhoto: livePhotoURL != nil
            )
            modelContext.insert(photo)
            try modelContext.save()
        }

        print("💾 [SaveService] After SwiftData save - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")
    }

    /// savephotophoto library
    private func savePhotoToAlbum(
        image: UIImage,
        originalImage: UIImage?,
        originalImageData: Data?,
        livePhotoVideoURL: URL?,
        originalLivePhotoVideoURL: URL?,
        metadata: [String: Any]?,
        saveOptions: SaveSettingsSnapshot,
        isRaw: Bool
    ) async throws -> (String, String?) {
        let orientationManager = OrientationManager.shared
        let locationManager = LocationManager.shared

        let deviceOrientation = orientationManager.currentDeviceOrientation
        let location = await locationManager.currentLocation
        let saveGPS = saveOptions.saveGPSEnabled
        let shouldSaveOriginal = saveOptions.saveOriginalEnabled &&
            (originalImage != nil || originalImageData != nil)

        // preparedataimage
        // ProRAW modeneed to original Data
        // Standard modeuse UIImage (support/result)
        let isProRaw = isRaw

        let finalOriginalImage: UIImage?
        let finalOriginalData: Data?

        if shouldSaveOriginal {
            finalOriginalData = originalImageData
            // if Standard mode originalImage, Data restore
            if !isProRaw, originalImage == nil, let data = originalImageData {
                finalOriginalImage = UIImage(data: data)
            } else {
                finalOriginalImage = originalImage
            }
        } else {
            finalOriginalImage = nil
            finalOriginalData = nil
        }

        if let liveURL = livePhotoVideoURL {
            return try await PerformanceMonitor.shared.monitorLivePhotoSave {
                try await PhotoAlbumManager.shared.saveLivePhotoToAlbum(
                    image: image,
                    livePhotoVideoURL: liveURL,
                    originalLivePhotoVideoURL: originalLivePhotoVideoURL,
                    metadata: metadata,
                    saveGPSEnabled: saveGPS,
                    currentLocation: location,
                    deviceOrientation: deviceOrientation,
                    originalImage: finalOriginalImage,
                    saveOptions: saveOptions
                )
            }
        } else {
            let result = try await PerformanceMonitor.shared.monitorAlbumSave {
                try await PhotoAlbumManager.shared.saveImageToAlbum(
                    image: image,
                    format: saveOptions.imageFileFormat,
                    originalImage: finalOriginalImage,
                    originalImageData: finalOriginalData,
                    isProRaw: isProRaw,
                    metadata: metadata,
                    saveGPSEnabled: saveGPS,
                    currentLocation: location,
                    deviceOrientation: deviceOrientation,
                    saveOptions: saveOptions
                )
            }
            return (result.assetIdentifier, result.originalAssetIdentifier)
        }
    }

    // MARK: - Video Saving

    private func saveVideo(videoURL: URL, originalVideoURL: URL? = nil, metadata: [String: Any]?, settings: SaveSettingsSnapshot) async throws {
        let orientationManager = OrientationManager.shared
        let locationManager = LocationManager.shared

        print("💾 [SaveService] 准备保存视频:")
        print("   - 带滤镜视频: \(videoURL.lastPathComponent)")
        print("   - 原始视频: \(originalVideoURL?.lastPathComponent ?? "无")")
        print("   - 保存原片开关: \(settings.saveOriginalEnabled)")

        let deviceOrientation = orientationManager.currentDeviceOrientation
        let location = await locationManager.currentLocation
        let saveGPS = settings.saveGPSEnabled
        let shouldSaveOriginal = settings.saveOriginalEnabled && (originalVideoURL != nil)

        // onlyoriginalsaveoriginalvideo
        let finalOriginalVideoURL = shouldSaveOriginal ? originalVideoURL : nil

        print("💾 [SaveService] 实际保存: 原始视频=\(finalOriginalVideoURL != nil ? "是" : "否")")

        // savevideophoto library
        let (assetIdentifier, originalAssetIdentifier) = try await PhotoAlbumManager.shared.saveVideoToAlbum(
            videoURL: videoURL,
            originalVideoURL: finalOriginalVideoURL,
            metadata: metadata,
            saveGPSEnabled: saveGPS,
            currentLocation: location,
            deviceOrientation: deviceOrientation,
            saveOptions: settings
        )

        let metadataData = try await serializeMetadata(metadata)

        // getvideo
        let duration = try? await AVURLAsset(url: videoURL).load(.duration).seconds

        // save SwiftData(need to main thread)
        try await MainActor.run { [weak self] in
            guard let self, let modelContext = self.modelContext else { return }
            let photo = PhotoAsset(
                assetIdentifier: assetIdentifier,
                originalAssetIdentifier: originalAssetIdentifier,
                metadata: metadataData,
                filterIdentifier: FilterManager.shared.selectedFilter,
                mediaType: 2, // video
                videoDuration: duration
            )
            modelContext.insert(photo)
            try modelContext.save()
        }
    }

    // MARK: - Utility Methods

    private func serializeMetadata(_ metadata: [String: Any]?) async throws -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let dict = metadata, !dict.isEmpty else { return nil }
            return DictionarySerializer.encodeDictionaryToData(dict)
        }.value
    }
}

// MARK: - Snapshot Model

/// capturesaveconfigure
struct SaveSettingsSnapshot {
    let captureQuality: CameraSettingsState.CaptureQuality
    let imageFileFormat: CameraSettingsState.ImageFileFormat
    let saveOriginalEnabled: Bool
    let saveGPSEnabled: Bool
    let effectiveFileNamingTemplate: String
    let fileNamingPrefix: String
    let copyrightEnabled: Bool
    let copyrightText: String
}

private extension CameraSaveService {
    /// main threadcurrentsaverelatedset
    func currentSaveSettingsSnapshot() async -> SaveSettingsSnapshot? {
        await MainActor.run { [weak self] in
            let settings = CameraSettingsState.shared
            return SaveSettingsSnapshot(
                captureQuality: settings.captureQuality,
                imageFileFormat: settings.imageFileFormat,
                saveOriginalEnabled: settings.saveOriginalEnabled,
                saveGPSEnabled: settings.saveGPSEnabled,
                effectiveFileNamingTemplate: settings.effectiveFileNamingTemplate,
                fileNamingPrefix: settings.fileNamingPrefix,
                copyrightEnabled: settings.copyrightEnabled,
                copyrightText: settings.copyrightText
            )
        }
    }
}

// MARK: - Errors

enum SaveError: Error, LocalizedError {
    case missingDependencies
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDependencies:
            return String.saveErrorMissingDependencies.localized
        case let .saveFailed(message):
            return String.saveErrorFailed.localized(message)
        }
    }
}
