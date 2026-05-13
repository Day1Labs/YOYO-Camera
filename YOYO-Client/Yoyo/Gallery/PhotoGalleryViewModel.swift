import Foundation
import Photos
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class PhotoGalleryViewModel: ObservableObject {
    @Published var photos: [PhotoAsset] = []
    @Published var isLoading = false
    @Published var loadingError: String? = nil
    @Published var isSelecting = false
    @Published var selectedPhotos: Set<PhotoAsset.ID> = []
    @Published var isGeneratingVideo = false
    @Published var generationProgress: Double = 0.0

    private var prefetchTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    private var modelContext: ModelContext?
    private var permissionManager: PermissionManager?

    init(initialPhotos: [PhotoAsset] = []) {
        photos = initialPhotos
        observeAppLifecycle()
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    func setup(modelContext: ModelContext, permissionManager: PermissionManager) {
        self.modelContext = modelContext
        self.permissionManager = permissionManager
    }

    func toggleSelectionMode() {
        withAnimation {
            isSelecting.toggle()
        }
        selectedPhotos.removeAll()
    }

    func toggleSelection(for photoId: PhotoAsset.ID) {
        selectedPhotos.formSymmetricDifference([photoId])
    }

    private func observeAppLifecycle() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.prefetchTask?.cancel()
            PhotoLoader.shared.clearCache()
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePrefetchRestart()
        }
    }

    private func schedulePrefetchRestart() {
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            await self.startPrefetchWorkIfNeeded()
        }
    }

    @MainActor
    private func startPrefetchWorkIfNeeded() {
        guard !photos.isEmpty else { return }
        let identifiersToCache = photos.prefix(40).map(\.assetIdentifier)
        prefetchTask?.cancel()
        prefetchTask = Task.detached(priority: .background) {
            await PhotoLoader.shared.startCachingThumbnails(for: identifiersToCache)
        }
    }

    func loadPhotos(skipValidation: Bool = false) async {
        guard !isLoading else { return }
        guard let modelContext, let permissionManager else { return }

        isLoading = true
        loadingError = nil

        do {
            guard permissionManager.hasPhotoLibraryPermission else {
                throw PhotoGalleryError.permissionDenied
            }

            let descriptor = FetchDescriptor<PhotoAsset>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )

            let allPhotos = try modelContext.fetch(descriptor)

            let validationResult: ValidationResult
            if skipValidation {
                validationResult = ValidationResult(photos: allPhotos, isReliable: true)
            } else {
                validationResult = await removeMissingAssets(from: allPhotos)
            }

            photos = validationResult.photos
            isLoading = false

            if validationResult.isReliable {
                await backfillMediaMetadata(for: validationResult.photos)
                await MainActor.run {
                    startPrefetchWork(for: validationResult.photos)
                }
            } else if validationResult.photos.isEmpty {
                loadingError = String.galleryTemporarilyUnavailable.localized
            }

        } catch {
            let errorMessage: String
            if let photoError = error as? PhotoGalleryError {
                errorMessage = photoError.localizedDescription
            } else {
                errorMessage = "加载照片失败: \(error.localizedDescription)"
            }

            loadingError = errorMessage
            isLoading = false
        }
    }

    private struct ValidationResult {
        let photos: [PhotoAsset]
        let isReliable: Bool
    }

    private func removeMissingAssets(from photos: [PhotoAsset]) async -> ValidationResult {
        guard !photos.isEmpty,
              let modelContext,
              permissionManager?.hasPhotoLibraryPermission == true,
              UIApplication.shared.applicationState == .active
        else {
            return ValidationResult(photos: photos, isReliable: true)
        }

        let identifiers = photos.map(\.assetIdentifier)
        let checkResult = await PhotoAlbumManager.shared.existingAssetIdentifiers(for: identifiers)

        guard checkResult.isReliable else {
            print("⚠️ [PhotoGallery] Photos fetch was unreliable; skipping destructive validation.")
            return ValidationResult(photos: photos, isReliable: false)
        }

        let existingSet = checkResult.existing
        let missing = photos.filter { !existingSet.contains($0.assetIdentifier) }

        if !missing.isEmpty {
            for p in missing {
                PhotoLoader.shared.removeCache(for: p.id.uuidString)
                if p.originalAssetIdentifier != nil {
                    PhotoLoader.shared.removeCache(for: "\(p.id.uuidString)_original_preview")
                    PhotoLoader.shared.removeCache(for: "\(p.id.uuidString)_original_full")
                }
                modelContext.delete(p)
            }
            try? modelContext.save()
        }

        let filteredPhotos = photos.filter { existingSet.contains($0.assetIdentifier) }
        return ValidationResult(photos: filteredPhotos, isReliable: true)
    }

    func deleteSelectedPhotos() {
        guard let modelContext, let permissionManager else { return }

        guard permissionManager.hasPhotoLibraryPermission else {
            permissionManager.checkPhotoLibraryPermission()
            return
        }

        let photosToDelete = photos.filter { selectedPhotos.contains($0.id) }
        let selectedCount = selectedPhotos.count
        AnalyticsManager.shared.log(.galleryAction(action: "batch_delete"))

        Task.detached(priority: .userInitiated) {
            do {
                var assetIdentifiersToDelete: [String] = []
                for photo in photosToDelete {
                    assetIdentifiersToDelete.append(photo.assetIdentifier)
                    if let originalAssetId = photo.originalAssetIdentifier {
                        assetIdentifiersToDelete.append(originalAssetId)
                    }
                }

                try await PhotoAlbumManager.shared.deletePhotosFromAlbum(assetIdentifiers: assetIdentifiersToDelete)

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.photos.removeAll { self.selectedPhotos.contains($0.id) }
                        self.selectedPhotos.removeAll()
                        self.isSelecting = false
                    }

                    let deletedIDs = Set(photosToDelete.map(\.id))

                    for photo in photosToDelete {
                        PhotoLoader.shared.removeCache(for: photo.id.uuidString)
                        if photo.originalAssetIdentifier != nil {
                            PhotoLoader.shared.removeCache(for: "\(photo.id.uuidString)_original_preview")
                            PhotoLoader.shared.removeCache(for: "\(photo.id.uuidString)_original_full")
                        }
                        self.modelContext?.delete(photo)
                    }

                    do {
                        try self.modelContext?.save()
                        print("批量删除 \(selectedCount) 张照片成功")
                    } catch {
                        print("保存 SwiftData 更改失败: \(error)")
                    }

                    self.startPrefetchWork(for: self.photos)
                }

            } catch {
                print("批量删除失败: \(error.localizedDescription)")
            }
        }
    }

    func generateVideoFromSelection() {
        guard selectedPhotos.count >= 2 else { return }

        let selectedSet = selectedPhotos
        isSelecting = false
        selectedPhotos.removeAll()

        isGeneratingVideo = true
        generationProgress = 0.0

        // Sort by timestamp
        let assetsToProcess = photos.filter { selectedSet.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }

        Task {
            do {
                let identifiers = assetsToProcess.map(\.assetIdentifier)
                let phAssets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)

                var assets: [PHAsset] = []
                phAssets.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }

                // Sort PHAssets to match our desired order
                let sortedAssets = assetsToProcess.compactMap { photoAsset in
                    assets.first(where: { $0.localIdentifier == photoAsset.assetIdentifier })
                }

                let videoURL = try await VideoGenerator.shared.generateVideo(from: sortedAssets) { progress in
                    Task { @MainActor in
                        self.generationProgress = progress
                    }
                }

                let duration = try? await AVURLAsset(url: videoURL).load(.duration).seconds
                let saveResult = try await PhotoAlbumManager.shared.saveVideoToAlbum(videoURL: videoURL)

                try await MainActor.run {
                    guard let modelContext = self.modelContext else { return }
                    let photo = PhotoAsset(
                        assetIdentifier: saveResult.assetIdentifier,
                        originalAssetIdentifier: saveResult.originalAssetIdentifier,
                        metadata: nil,
                        filterIdentifier: nil,
                        mediaType: 2,
                        videoDuration: duration
                    )
                    modelContext.insert(photo)
                    try modelContext.save()
                    self.photos.insert(photo, at: 0)
                    self.startPrefetchWork(for: self.photos)
                }

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.isGeneratingVideo = false
                    self.isSelecting = false
                    self.selectedPhotos.removeAll()
                    self.generationProgress = 0.0
                }

            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    self.isGeneratingVideo = false
                    self.loadingError = "生成视频失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func backfillMediaMetadata(for photos: [PhotoAsset]) async {
        let photosToBackfill = photos.filter { $0.mediaType == 0 }
        guard !photosToBackfill.isEmpty else { return }

        let identifiers = photosToBackfill.map(\.assetIdentifier)
        let assets = await Task.detached(priority: .userInitiated) {
            PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        }.value

        var assetByIdentifier: [String: PHAsset] = [:]
        assets.enumerateObjects { asset, _, _ in
            assetByIdentifier[asset.localIdentifier] = asset
        }

        for photo in photosToBackfill {
            if let asset = assetByIdentifier[photo.assetIdentifier] {
                photo.mediaType = asset.mediaType.rawValue
                photo.isLivePhoto = asset.mediaSubtypes.contains(.photoLive) && asset.mediaType == .image
                photo.videoDuration = asset.mediaType == .video ? asset.duration : nil
            }
        }

        try? modelContext?.save()
    }

    func startPrefetchWork(for photos: [PhotoAsset]) {
        prefetchTask?.cancel()

        guard !photos.isEmpty, UIApplication.shared.applicationState == .active else { return }

        let identifiersToCache = photos.prefix(40).map(\.assetIdentifier)

        prefetchTask = Task.detached(priority: .background) {
            await PhotoLoader.shared.startCachingThumbnails(for: identifiersToCache)
        }
    }

    func onDisappear() {
        prefetchTask?.cancel()
        PhotoLoader.shared.stopCachingAllImages()
    }
}
