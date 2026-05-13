import AVFoundation
import CoreGraphics
import CoreLocation
import CoreMedia
import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

final class PhotoAlbumManager {
    static let shared = PhotoAlbumManager()

    private let albumName = "Yoyo"
    private var yoyoAlbum: PHAssetCollection?
    private let jpegQuality: CGFloat = 0.75
    private let heicQuality: CGFloat = 0.75

    private init() {}

    /// Get current memory usage in MB.
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

    // MARK: - Public Methods

    func saveImageToAlbum(
        image: UIImage,
        format: CameraSettingsState.ImageFileFormat = .heic,
        originalImage: UIImage? = nil,
        originalImageData: Data? = nil,
        isProRaw: Bool = false,
        metadata: [String: Any]? = nil,
        saveGPSEnabled: Bool = false,
        currentLocation: CLLocation? = nil,
        deviceOrientation: UIDeviceOrientation? = nil,
        saveOptions: SaveSettingsSnapshot? = nil
    ) async throws -> (assetIdentifier: String, originalAssetIdentifier: String?) {
        print("📸 [PhotoAlbum] saveImageToAlbum start - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        let album = try await getOrCreateYoyoAlbum()
        print("📸 [PhotoAlbum] after getOrCreateYoyoAlbum - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        let finalMetadata = await prepareMetadata(
            metadata,
            deviceOrientation: deviceOrientation,
            location: saveGPSEnabled ? currentLocation : nil,
            saveOptions: saveOptions
        )

        // Process images serially to avoid holding two large images at once.
        // Process the filtered image first.
        let processedFileURL = await generateImageFile(
            image: image,
            format: format,
            metadata: finalMetadata,
            saveOptions: saveOptions,
            fileType: .photo,
            isOriginal: false
        )
        print("📸 [PhotoAlbum] after generateImageFile (filtered) - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        // Then process the original image if it exists.
        var originalFileURL: URL?
        var originalFormat = format

        if isProRaw, let data = originalImageData {
            // ProRAW: Save raw data directly            print("📸 [PhotoAlbum] Saving ProRAW original")
            originalFileURL = await generateRawImageFile(
                data: data,
                saveOptions: saveOptions,
                isOriginal: true
            )
        } else if let originalImage {
            // Standard mode prefers HEIC for the original image when the active format is JPEG.
            let targetFormat: CameraSettingsState.ImageFileFormat = (format == .jpeg) ? .heic : format
            originalFormat = targetFormat

            originalFileURL = await generateImageFile(
                image: originalImage,
                format: targetFormat,
                metadata: finalMetadata,
                saveOptions: saveOptions,
                fileType: .photo,
                isOriginal: true
            )
            print("📸 [PhotoAlbum] after generateImageFile (original) - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")
        }

        print("📸 [PhotoAlbum] after all generateImageFile - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        let result = try await saveAssetsToAlbum(
            album: album,
            processedFileURL: processedFileURL,
            originalFileURL: originalFileURL,
            processedFormat: format,
            originalFormat: originalFormat,
            isProRawOriginal: isProRaw,
            saveGPSEnabled: saveGPSEnabled,
            currentLocation: currentLocation
        )

        print("📸 [PhotoAlbum] after saveAssetsToAlbum - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        // Clean temporary files, consistent with the Live Photo flow.
        let filesToCleanup = [processedFileURL, originalFileURL].compactMap { $0 }
        print("🔬 [MemoryDebug] 准备清理临时文件: \(filesToCleanup.map(\.lastPathComponent))")
        await FileManager.safeRemoveItems(at: filesToCleanup)
        print("📸 [PhotoAlbum] after cleanup temp files - Memory: \(String(format: "%.1f", getMemoryUsage()))MB")

        return result
    }

    /// Save LivePhoto to Album    /// - Parameters:
    ///   - image: filter image    ///   - livePhotoVideoURL: processed video URL    ///   - originalLivePhotoVideoURL: original video URL (optional)    ///   - originalImage: original image (optional)    /// - Returns: (assetIdentifier, originalAssetIdentifier)
    func saveLivePhotoToAlbum(
        image: UIImage,
        livePhotoVideoURL: URL,
        originalLivePhotoVideoURL: URL? = nil,
        metadata: [String: Any]? = nil,
        saveGPSEnabled: Bool = false,
        currentLocation: CLLocation? = nil,
        deviceOrientation: UIDeviceOrientation? = nil,
        originalImage: UIImage? = nil,
        saveOptions: SaveSettingsSnapshot? = nil
    ) async throws -> (assetIdentifier: String, originalAssetIdentifier: String?) {
        _ = try await getOrCreateYoyoAlbum()
        let finalMetadata = await prepareMetadata(
            metadata,
            deviceOrientation: deviceOrientation,
            location: saveGPSEnabled ? currentLocation : nil,
            saveOptions: saveOptions
        )

        // Generate image files in parallel and include Live Photo pairing metadata.
        let (imageFileURL, originalFileURL) = await withTaskGroup(of: (isOriginal: Bool, url: URL?).self) { group in
            // Task 1: generate the processed image.
            group.addTask(priority: .userInitiated) {
                let url = await self.generateImageFile(
                    image: image,
                    format: .heic,
                    metadata: finalMetadata,
                    saveOptions: saveOptions,
                    fileType: .livePhoto,
                    isOriginal: false
                )
                return (isOriginal: false, url: url)
            }

            // Task 2: generate the original image if it exists.
            if let originalImage {
                group.addTask(priority: .userInitiated) {
                    var originalMetadata = finalMetadata
                    originalMetadata.removeValue(forKey: "livePhotoAssetIdentifier")

                    if let originalVideoURL = originalLivePhotoVideoURL,
                       let id = await self.getContentIdentifier(from: originalVideoURL)
                    {
                        originalMetadata["livePhotoAssetIdentifier"] = id
                    }

                    let url = await self.generateImageFile(
                        image: originalImage,
                        format: .heic,
                        metadata: originalMetadata,
                        saveOptions: saveOptions,
                        fileType: .livePhoto,
                        isOriginal: true
                    )
                    return (isOriginal: true, url: url)
                }
            }

            var processedURL: URL?
            var originalURL: URL?

            for await result in group {
                if result.isOriginal {
                    originalURL = result.url
                } else {
                    processedURL = result.url
                }
            }

            return (processedURL, originalURL)
        }

        guard let imageFileURL else {
            throw PhotoAlbumError.photoSaveFailed
        }

        return try await withThrowingTaskGroup(of: String.self) { group in
            var livePhotoIdentifier: String?
            var originalLivePhotoIdentifier: String?

            // Task 1: save the processed image as a Live Photo.
            group.addTask {
                try await self.saveLivePhotoAssetDirectly(
                    imageFileURL: imageFileURL,
                    videoURL: livePhotoVideoURL,
                    saveGPSEnabled: saveGPSEnabled,
                    currentLocation: currentLocation
                )
            }

            // Task 2: save the original image as a Live Photo when both assets exist.
            if let originalFileURL, let originalVideoURL = originalLivePhotoVideoURL {
                group.addTask {
                    try await self.saveLivePhotoAssetDirectly(
                        imageFileURL: originalFileURL,
                        videoURL: originalVideoURL,
                        saveGPSEnabled: saveGPSEnabled,
                        currentLocation: currentLocation
                    )
                }
            }

            // Collect all results.
            var identifiers: [String] = []
            for try await identifier in group {
                identifiers.append(identifier)
            }

            if identifiers.count >= 2 {
                livePhotoIdentifier = identifiers[0]
                originalLivePhotoIdentifier = identifiers[1]
            } else if identifiers.count == 1 {
                livePhotoIdentifier = identifiers[0]
            }

            // Clean temporary files.
            await FileManager.safeRemoveItems(at: [imageFileURL, originalFileURL].compactMap { $0 })

            return (livePhotoIdentifier ?? "", originalLivePhotoIdentifier)
        }
    }

    // MARK: - LivePhoto Helper Methods

    /// Read the content identifier from a video file.
    private func getContentIdentifier(from videoURL: URL) async -> String? {
        let asset = AVURLAsset(url: videoURL)
        let key = "com.apple.quicktime.content.identifier"
        let keySpace = "mdta"

        do {
            // iOS 15+ uses `load(.metadata)`.
            if #available(iOS 15.0, *) {
                let metadata = try await asset.load(.metadata)
                for item in metadata {
                    if item.key as? String == key, item.keySpace?.rawValue == keySpace {
                        return item.value as? String
                    }
                }
            } else {
                // Fallback for older iOS versions (if needed, though project seems to be iOS 18+)
                let metadata = asset.metadata
                for item in metadata {
                    if item.key as? String == key, item.keySpace?.rawValue == keySpace {
                        return item.value as? String
                    }
                }
            }
        } catch {
            print("❌ [LivePhoto] Failed to load metadata from original video: \(error)")
        }
        return nil
    }

    /// Save a Live Photo directly when image and video already contain correct metadata.
    private func saveLivePhotoAssetDirectly(
        imageFileURL: URL,
        videoURL: URL,
        saveGPSEnabled: Bool,
        currentLocation: CLLocation?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var placeholder: PHObjectPlaceholder?

            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true

                creationRequest.addResource(with: .photo, fileURL: imageFileURL, options: options)
                creationRequest.addResource(with: .pairedVideo, fileURL: videoURL, options: options)

                if saveGPSEnabled, let location = currentLocation {
                    creationRequest.location = location
                }
                creationRequest.creationDate = Date()

                placeholder = creationRequest.placeholderForCreatedAsset
            }) { success, error in
                if success, let id = placeholder?.localIdentifier {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(throwing: error ?? PhotoAlbumError.photoSaveFailed)
                }
            }
        }
    }

    func saveVideoToAlbum(
        videoURL: URL,
        originalVideoURL: URL? = nil,
        metadata _: [String: Any]? = nil,
        saveGPSEnabled: Bool = false,
        currentLocation: CLLocation? = nil,
        deviceOrientation _: UIDeviceOrientation? = nil,
        saveOptions _: SaveSettingsSnapshot? = nil
    ) async throws -> (assetIdentifier: String, originalAssetIdentifier: String?) {
        let album = try await getOrCreateYoyoAlbum()

        return try await withThrowingTaskGroup(of: (isOriginal: Bool, identifier: String).self) { group in
            // Task 1: save the processed video.
            group.addTask {
                let identifier = try await self.saveVideoAssetToAlbum(
                    album: album,
                    videoURL: videoURL,
                    saveGPSEnabled: saveGPSEnabled,
                    currentLocation: currentLocation
                )
                return (isOriginal: false, identifier: identifier)
            }

            // Task 2: save the original video if it exists.
            if let originalVideoURL {
                group.addTask {
                    let identifier = try await self.saveVideoAssetToAlbum(
                        album: album,
                        videoURL: originalVideoURL,
                        saveGPSEnabled: saveGPSEnabled,
                        currentLocation: currentLocation
                    )
                    return (isOriginal: true, identifier: identifier)
                }
            }

            // Collect results.
            var processedIdentifier: String?
            var originalIdentifier: String?

            for try await result in group {
                if result.isOriginal {
                    originalIdentifier = result.identifier
                } else {
                    processedIdentifier = result.identifier
                }
            }

            return (processedIdentifier ?? "", originalIdentifier)
        }
    }

    func deletePhotosFromAlbum(assetIdentifiers: [String]) async throws {
        guard !assetIdentifiers.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        let assetsToDelete = fetchResult.objects(at: IndexSet(0 ..< fetchResult.count))

        guard !assetsToDelete.isEmpty else {
            throw PhotoAlbumError.assetNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoAlbumError.photoDeleteFailed)
                }
            }
        }
    }

    func deletePhotoFromAlbum(assetIdentifier: String) async throws {
        try await deletePhotosFromAlbum(assetIdentifiers: [assetIdentifier])
    }

    // MARK: - Private Methods

    private func getOrCreateYoyoAlbum() async throws -> PHAssetCollection {
        if let existingAlbum = yoyoAlbum {
            return existingAlbum
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        if let existingCollection = collections.firstObject {
            yoyoAlbum = existingCollection
            return existingCollection
        }

        return try await createNewAlbum()
    }

    private func createNewAlbum() async throws -> PHAssetCollection {
        try await withCheckedThrowingContinuation { continuation in
            var albumPlaceholder: PHObjectPlaceholder?

            PHPhotoLibrary.shared().performChanges({
                let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                albumPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
            }) { success, error in
                if success, let placeholder = albumPlaceholder {
                    let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                    if let album = fetchResult.firstObject {
                        Task { @MainActor in
                            self.yoyoAlbum = album
                        }
                        continuation.resume(returning: album)
                    } else {
                        continuation.resume(throwing: PhotoAlbumError.albumCreationFailed)
                    }
                } else {
                    continuation.resume(throwing: error ?? PhotoAlbumError.albumCreationFailed)
                }
            }
        }
    }

    private func saveAssetsToAlbum(
        album: PHAssetCollection,
        processedFileURL: URL?,
        originalFileURL: URL?,
        processedFormat: CameraSettingsState.ImageFileFormat,
        originalFormat: CameraSettingsState.ImageFileFormat,
        isProRawOriginal: Bool,
        saveGPSEnabled: Bool,
        currentLocation: CLLocation?
    ) async throws -> (assetIdentifier: String, originalAssetIdentifier: String?) {
        // Verify file existence.
        if let processedURL = processedFileURL {
            guard FileManager.default.fileExists(atPath: processedURL.path) else {
                print("❌ [PhotoAlbum] Processed file doesn't exist: \(processedURL.path)")
                throw PhotoAlbumError.photoSaveFailed
            }
        }

        if let originalURL = originalFileURL {
            guard FileManager.default.fileExists(atPath: originalURL.path) else {
                print("❌ [PhotoAlbum] Original file doesn't exist: \(originalURL.path)")
                throw PhotoAlbumError.photoSaveFailed
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            var processedPlaceholder: PHObjectPlaceholder?
            var originalPlaceholder: PHObjectPlaceholder?

            PHPhotoLibrary.shared().performChanges({
                // Create processed asset
                if let processedURL = processedFileURL {
                    processedPlaceholder = self.createPhotoAsset(
                        fileURL: processedURL,
                        uti: self.getUTI(for: processedFormat),
                        location: saveGPSEnabled ? currentLocation : nil
                    )
                }

                // Create original asset
                if let originalURL = originalFileURL {
                    let originalUTI: String
                    if isProRawOriginal {
                        originalUTI = UTType.rawImage.identifier // DNG
                    } else {
                        originalUTI = self.getUTI(for: originalFormat)
                    }

                    originalPlaceholder = self.createPhotoAsset(
                        fileURL: originalURL,
                        uti: originalUTI,
                        location: saveGPSEnabled ? currentLocation : nil
                    )
                }

                // Add to album
                if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                    let assets = [processedPlaceholder, originalPlaceholder].compactMap { $0 }
                    if !assets.isEmpty {
                        albumChangeRequest.addAssets(assets as NSArray)
                    }
                }
            }) { success, error in
                if success, let processed = processedPlaceholder {
                    print("✅ [PhotoAlbum] Save successful - assetID: \(processed.localIdentifier)")
                    continuation.resume(returning: (processed.localIdentifier, originalPlaceholder?.localIdentifier))
                } else {
                    print("❌ [PhotoAlbum] Save failed: \(error?.localizedDescription ?? "unknown")")
                    // Cleanup on failure
                    [processedFileURL, originalFileURL].compactMap { $0 }.forEach { url in
                        try? FileManager.default.removeItem(at: url)
                    }
                    continuation.resume(throwing: error ?? PhotoAlbumError.photoSaveFailed)
                }
            }
        }
    }

    // MARK: - Image Generation

    /// Generate RAW files.
    private func generateRawImageFile(
        data: Data,
        saveOptions: SaveSettingsSnapshot?,
        isOriginal: Bool
    ) async -> URL? {
        let fileURL = await MainActor.run {
            makeTempURL(ext: "dng", saveOptions: saveOptions, fileType: .photo, isOriginal: isOriginal)
        }

        // Ensure the directory exists.
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }

        // Remove the existing file first when needed.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                return nil
            }
        }

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("❌ [PhotoAlbum] Failed to write RAW file: \(error)")
            return nil
        }
    }

    /// Optimize memory management to avoid keeping `UIImage` alive too long.
    private func generateImageFile(
        image: UIImage,
        format: CameraSettingsState.ImageFileFormat,
        metadata: [String: Any],
        saveOptions: SaveSettingsSnapshot?,
        fileType: FileType,
        isOriginal: Bool = false
    ) async -> URL? {
        let ext = format == .jpeg ? "jpg" : "heic"

        let fileURL = await MainActor.run {
            makeTempURL(ext: ext, saveOptions: saveOptions, fileType: fileType, isOriginal: isOriginal)
        }
        print("🔬 [MemoryDebug] generateImageFile - isOriginal: \(isOriginal), fileURL: \(fileURL.lastPathComponent)")

        // Ensure the directory exists.
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }

        // Remove the existing file first when needed.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                return nil
            }
        }

        // Process on the current thread and wrap in `autoreleasepool` to release intermediates quickly.
        let result: URL? = autoreleasepool {
            createImageFile(image: image, format: format, metadata: metadata, fileURL: fileURL)
        }

        // Verify that the file was created successfully.
        if let result, FileManager.default.fileExists(atPath: result.path) {
            return result
        }
        return nil
    }

    private func createImageFile(image: UIImage, format: CameraSettingsState.ImageFileFormat, metadata: [String: Any], fileURL: URL) -> URL? {
        let isJPEG = (format == .jpeg)
        let quality = isJPEG ? jpegQuality : heicQuality

        var finalMetadata = metadata

        // Handle the Live Photo asset identifier.
        if let assetIdentifier = metadata["livePhotoAssetIdentifier"] as? String {
            let assetIdentifierKey = "17"
            let assetIdentifierInfo = [assetIdentifierKey: assetIdentifier]
            finalMetadata[kCGImagePropertyMakerAppleDictionary as String] = assetIdentifierInfo
            finalMetadata.removeValue(forKey: "livePhotoAssetIdentifier")
        }

        finalMetadata[kCGImagePropertyHasAlpha as String] = false
        let colorSpace = image.cgImage?.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        if let name = colorSpace?.name {
            finalMetadata[kCGImagePropertyProfileName as String] = name
        }
        if !isJPEG {
            finalMetadata[kCGImageDestinationLossyCompressionQuality as String] = quality
        }

        if isJPEG {
            // Wrap JPEG processing in `autoreleasepool`.
            return autoreleasepool {
                guard let baseData = image.jpegData(compressionQuality: quality),
                      let source = CGImageSourceCreateWithData(baseData as CFData, nil),
                      let sourceUTI = CGImageSourceGetType(source),
                      let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, sourceUTI, 1, nil)
                else {
                    return nil
                }

                CGImageDestinationAddImageFromSource(dest, source, 0, finalMetadata as CFDictionary)
                let success = CGImageDestinationFinalize(dest)
                // `source` and `baseData` are released at the end of `autoreleasepool`.
                return success && FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
            }
        } else {
            // Wrap HEIC processing in `autoreleasepool`.
            return autoreleasepool {
                guard #available(iOS 11.0, *), let cgImage = image.cgImage else {
                    return nil
                }

                let uti = UTType.heic.identifier as CFString
                let destOptions: [CFString: Any] = [
                    kCGImageDestinationOptimizeColorForSharing: false,
                ]

                guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, uti, 1, destOptions as CFDictionary) else {
                    return nil
                }

                var heicMetadata = finalMetadata
                heicMetadata[kCGImageDestinationEmbedThumbnail as String] = false
                if let name = colorSpace?.name {
                    heicMetadata[kCGImagePropertyProfileName as String] = name
                }
                if CGColorSpace(name: CGColorSpace.displayP3) != nil {
                    heicMetadata[kCGImagePropertyColorModel as String] = kCGImagePropertyColorModelRGB
                }

                CGImageDestinationAddImage(dest, cgImage, heicMetadata as CFDictionary)
                let success = CGImageDestinationFinalize(dest)
                // `cgImage` is released at the end of `autoreleasepool`.
                return success && FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
            }
        }
    }

    // MARK: - Utility Methods

    @MainActor
    private func makeTempURL(ext: String, saveOptions: SaveSettingsSnapshot?, fileType: FileType, isOriginal: Bool = false) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let name: String
        if let options = saveOptions {
            // Use the user-configured filename format.
            let fileFormat: FileFormat
            if ext == "jpg" { fileFormat = .jpg }
            else if ext == "heic" { fileFormat = .heic }
            else if ext == "dng" { fileFormat = .dng }
            else if ext == "mov" { fileFormat = .mov }
            else { fileFormat = .mp4 }

            name = FileNameGenerator.shared.generateFullFileName(
                template: options.effectiveFileNamingTemplate,
                prefix: options.fileNamingPrefix,
                fileType: fileType,
                fileFormat: fileFormat,
                isOriginal: isOriginal
            )
        } else {
            // Default format.
            let suffix = isOriginal ? "_original" : ""
            name = "yoyo\(suffix)_\(UUID().uuidString).\(ext)"
        }

        return dir.appendingPathComponent(name)
    }

    private func getUTI(for format: CameraSettingsState.ImageFileFormat) -> String {
        switch format {
        case .jpeg:
            return UTType.jpeg.identifier
        case .heic:
            return UTType.heic.identifier
        }
    }

    @MainActor
    private func prepareMetadata(_ metadata: [String: Any]?, deviceOrientation: UIDeviceOrientation?, location: CLLocation?, saveOptions: SaveSettingsSnapshot?) -> [String: Any] {
        var finalMetadata = metadata ?? [:]

        // Set orientation based on device orientation
        let orientationValue = orientationFromDeviceOrientation(deviceOrientation)
        finalMetadata[String(kCGImagePropertyOrientation)] = orientationValue

        // Update TIFF dictionary
        var tiff = finalMetadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any] ?? [:]

        if orientationValue != 1 {
            tiff[String(kCGImagePropertyTIFFOrientation)] = orientationValue
        }

        // Add copyright to TIFF dictionary if enabled
        if let options = saveOptions, options.copyrightEnabled, !options.copyrightText.isEmpty {
            tiff[String(kCGImagePropertyTIFFCopyright)] = options.copyrightText
        }

        if !tiff.isEmpty {
            finalMetadata[String(kCGImagePropertyTIFFDictionary)] = tiff
        }

        // Add GPS data if location is provided
        if let location {
            finalMetadata[String(kCGImagePropertyGPSDictionary)] = createGPSDict(from: location)
        }

        return finalMetadata
    }

    private func orientationFromDeviceOrientation(_ deviceOrientation: UIDeviceOrientation?) -> Int {
        guard let deviceOrientation else {
            return 1
        }

        switch deviceOrientation {
        case .portrait:
            return 1
        case .portraitUpsideDown:
            return 3
        case .landscapeRight:
            return 6
        case .landscapeLeft:
            return 8
        default:
            return 1
        }
    }

    private func createGPSDict(from location: CLLocation) -> [String: Any] {
        let coordinate = location.coordinate
        let altitude = location.altitude

        var gpsDict: [String: Any] = [:]

        gpsDict[String(kCGImagePropertyGPSLatitude)] = abs(coordinate.latitude)
        gpsDict[String(kCGImagePropertyGPSLatitudeRef)] = coordinate.latitude >= 0 ? "N" : "S"
        gpsDict[String(kCGImagePropertyGPSLongitude)] = abs(coordinate.longitude)
        gpsDict[String(kCGImagePropertyGPSLongitudeRef)] = coordinate.longitude >= 0 ? "E" : "W"

        if altitude != -1 {
            gpsDict[String(kCGImagePropertyGPSAltitude)] = abs(altitude)
            gpsDict[String(kCGImagePropertyGPSAltitudeRef)] = altitude >= 0 ? 0 : 1
        }

        if location.horizontalAccuracy >= 0 {
            gpsDict[String(kCGImagePropertyGPSHPositioningError)] = location.horizontalAccuracy
        }

        return gpsDict
    }

    func existingAssetIdentifiers(for identifiers: [String]) async -> AssetIdentifierCheckResult {
        guard !identifiers.isEmpty else {
            return AssetIdentifierCheckResult(existing: [], isReliable: true)
        }

        let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
        guard isActive else {
            return AssetIdentifierCheckResult(existing: [], isReliable: false)
        }

        return await Task.detached(priority: .userInitiated) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            var existing = Set<String>()
            fetchResult.enumerateObjects { asset, _, _ in
                existing.insert(asset.localIdentifier)
            }

            let isReliable = !existing.isEmpty
            if !isReliable {
                print("⚠️ [PhotoAlbumManager] Photos fetch returned 0 of \(identifiers.count) identifiers; treating as transient.")
            }

            return AssetIdentifierCheckResult(existing: existing, isReliable: isReliable)
        }.value
    }

    private func createPhotoAsset(fileURL: URL, uti: String, location: CLLocation?) -> PHObjectPlaceholder? {
        // Simplified validation: only check file existence and size.
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ [PhotoAlbumManager] File doesn't exist: \(fileURL.path)")
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            if fileSize == 0 {
                print("❌ [PhotoAlbumManager] File is empty: \(fileURL.path)")
                return nil
            }
        } catch {
            print("❌ [PhotoAlbumManager] File validation failed: \(error.localizedDescription)")
            return nil
        }

        let creationRequest = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.uniformTypeIdentifier = uti

        // Use move instead of copy so Photos can clean up temp files automatically.
        options.shouldMoveFile = true

        creationRequest.addResource(with: .photo, fileURL: fileURL, options: options)

        if let location {
            creationRequest.location = location
        }

        creationRequest.creationDate = Date()
        return creationRequest.placeholderForCreatedAsset
    }

    private func saveVideoAssetToAlbum(
        album: PHAssetCollection,
        videoURL: URL,
        saveGPSEnabled: Bool,
        currentLocation: CLLocation?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var assetPlaceholder: PHObjectPlaceholder?

            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true

                creationRequest.addResource(with: .video, fileURL: videoURL, options: options)
                if saveGPSEnabled, let location = currentLocation {
                    creationRequest.location = location
                }
                creationRequest.creationDate = Date()
                assetPlaceholder = creationRequest.placeholderForCreatedAsset

                if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
                   let placeholder = assetPlaceholder
                {
                    albumChangeRequest.addAssets([placeholder] as NSArray)
                }
            }) { success, error in
                if success, let placeholder = assetPlaceholder {
                    continuation.resume(returning: placeholder.localIdentifier)
                } else {
                    try? FileManager.default.removeItem(at: videoURL)
                    continuation.resume(throwing: error ?? PhotoAlbumError.videoSaveFailed)
                }
            }
        }
    }

    // MARK: - Favorite Methods

    func toggleFavorite(for assetIdentifier: String, isFavorite: Bool) async throws {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw PhotoAlbumError.assetNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = isFavorite
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoAlbumError.photoSaveFailed)
                }
            }
        }
    }
}

struct AssetIdentifierCheckResult {
    let existing: Set<String>
    let isReliable: Bool
}

enum PhotoAlbumError: Error, LocalizedError {
    case albumCreationFailed
    case photoSaveFailed
    case photoDeleteFailed
    case permissionDenied
    case assetNotFound
    case videoSaveFailed

    var errorDescription: String? {
        switch self {
        case .albumCreationFailed:
            return String.albumErrorCreationFailed.localized
        case .photoSaveFailed:
            return String.albumErrorPhotoSaveFailed.localized
        case .photoDeleteFailed:
            return String.albumErrorPhotoDeleteFailed.localized
        case .permissionDenied:
            return String.albumErrorPermissionDenied.localized
        case .assetNotFound:
            return String.albumErrorAssetNotFound.localized
        case .videoSaveFailed:
            return String.albumErrorVideoSaveFailed.localized
        }
    }
}
