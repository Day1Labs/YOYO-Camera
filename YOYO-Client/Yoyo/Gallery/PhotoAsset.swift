import Foundation
import Photos
import SwiftData
import UIKit

@Model
final class PhotoAsset: Identifiable {
    var id: UUID
    var timestamp: Date
    var assetIdentifier: String // Resource identifier of the processed image in the system album
    var originalAssetIdentifier: String? // Resource identifier of the original picture in the system album
    var title: String
    var isFavorite: Bool
    var metadata: Data?
    var filterName: String? // Save filter type
    var aestheticsScore: Float? // Image aesthetic rating
    // Media metadata caching (persistence).
    var mediaType: Int = 0 // PHAssetMediaType rawValue (0: unknown, 1: image, 2: video)
    var isLivePhoto: Bool = false
    var videoDuration: TimeInterval?

    @Transient private var thumbnailCache: UIImage?

    var filterIdentifier: FilterIdentifier? {
        get {
            guard let raw = filterName, !raw.isEmpty else { return nil }
            // Parse "category:name" format.
            let parts = raw.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let category = FilterCategory(rawValue: String(parts[0])) {
                return FilterIdentifier(category: category, name: String(parts[1]))
            }
            // Compatible with older formats: try a built-in filter name.
            if BuiltinFilterRegistry.shared.contains(raw) {
                return .builtin(raw)
            }
            return nil
        }
        set {
            filterName = newValue?.id
        }
    }

    /// Main initializer that accepts a system album resource identifier.
    init(assetIdentifier: String, originalAssetIdentifier: String? = nil, title: String = "", metadata: Data? = nil, filterIdentifier: FilterIdentifier? = nil, mediaType: Int = 0, isLivePhoto: Bool = false, videoDuration: TimeInterval? = nil) {
        id = UUID()
        let currentDate = Date()
        timestamp = currentDate
        self.assetIdentifier = assetIdentifier
        self.originalAssetIdentifier = originalAssetIdentifier
        self.title = title.isEmpty ? "Photo \(DateFormatter.shortDateFormatter.string(from: currentDate))" : title
        isFavorite = false
        self.metadata = metadata
        filterName = filterIdentifier?.id
        self.mediaType = mediaType
        self.isLivePhoto = isLivePhoto
        self.videoDuration = videoDuration
    }

    /// Preview-only initializer that creates a temporary photo object.
    init(previewAssetIdentifier: String = "preview", title: String = "Preview Photo", mediaType: Int = 1, isLivePhoto: Bool = false) {
        id = UUID()
        timestamp = Date()
        assetIdentifier = previewAssetIdentifier
        originalAssetIdentifier = nil
        self.title = title
        isFavorite = false
        metadata = nil
        filterName = nil
        aestheticsScore = nil
        self.mediaType = mediaType
        self.isLivePhoto = isLivePhoto
    }

    func loadThumbnail() async -> UIImage? {
        if let cached = thumbnailCache { return cached }
        let image = await PhotoLoader.shared.loadThumbnail(from: assetIdentifier, key: id.uuidString)
        thumbnailCache = image
        return image
    }

    func loadFullImage() async -> UIImage? {
        await PhotoLoader.shared.loadFullImage(from: assetIdentifier, key: "\(id.uuidString)_full")
    }

    func loadOriginalImage(targetSize: CGSize = PHImageManagerMaximumSize, cacheKeySuffix: String? = nil) async -> UIImage? {
        let targetAssetId = originalAssetIdentifier ?? assetIdentifier

        // Use different cache keys to avoid preview and full-size collisions.
        let isFullResolution = targetSize.width >= PHImageManagerMaximumSize.width && targetSize.height >= PHImageManagerMaximumSize.height
        let suffix = cacheKeySuffix ?? (isFullResolution ? "original_full" : "original_preview")
        let cacheKey = "\(id.uuidString)_\(suffix)"

        return await PhotoLoader.shared.loadOriginalImage(from: targetAssetId, key: cacheKey, targetSize: targetSize)
    }

    func isLivePhoto(for targetAssetIdentifier: String) async -> Bool {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [targetAssetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return false }
        return asset.mediaSubtypes.contains(.photoLive)
    }

    func isVideo(for targetAssetIdentifier: String) async -> Bool {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [targetAssetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return false }
        return asset.mediaType == .video
    }

    func getVideoDuration(for targetAssetIdentifier: String) async -> TimeInterval? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [targetAssetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject, asset.mediaType == .video else { return nil }
        return asset.duration
    }

    func getLocation(for targetAssetIdentifier: String) async -> CLLocation? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [targetAssetIdentifier], options: nil)
        return fetchResult.firstObject?.location
    }

    /// Supplement the location name and persist it into metadata.
    func enrichLocationNameIfNeeded() async {
        // Skip when a location name already exists.
        if let metadata = metadataDict, metadata["locationName"] != nil {
            return
        }

        // Load the current location.
        guard let location = await getLocation(for: assetIdentifier) else {
            return
        }

        // Reverse geocode the location name.
        if let name = await GeocodingManager.shared.reverseGeocode(location) {
            await MainActor.run {
                var currentMetadata = self.metadataDict ?? [:]
                currentMetadata["locationName"] = name
                if let newData = DictionarySerializer.encodeDictionaryToData(currentMetadata) {
                    self.metadata = newData
                }
            }
        }
    }

    func loadLivePhoto() async -> PHLivePhoto? {
        await PhotoLoader.shared.loadLivePhoto(from: assetIdentifier, key: id.uuidString, isOriginal: false)
    }

    func loadOriginalLivePhoto() async -> PHLivePhoto? {
        guard let originalId = originalAssetIdentifier else { return nil }
        return await PhotoLoader.shared.loadLivePhoto(from: originalId, key: "\(id.uuidString)_original", isOriginal: true)
    }

    /// Decode metadata into a dictionary.
    var metadataDict: [String: Any]? {
        guard let metadata else { return nil }
        return DictionarySerializer.decodeDictionaryFromData(metadata)
    }
}

extension DateFormatter {
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = LanguageManager.shared.locale
        return formatter
    }()
}
