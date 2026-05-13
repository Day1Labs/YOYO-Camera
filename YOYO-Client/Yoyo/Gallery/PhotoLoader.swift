import Foundation
import Photos
import SwiftUI
import UIKit

@MainActor
final class PhotoLoader: ObservableObject {
    static let shared = PhotoLoader()

    /// Calculate thumbnail size based on screen scale for high-resolution devices.
    static let thumbnailSize: CGSize = {
        let scale = UIScreen.main.scale
        let dimension = 150 * scale
        return CGSize(width: dimension, height: dimension)
    }()

    static let detailMaxSize = CGSize(width: 2048, height: 2048)

    private let imageCache = NSCache<NSString, UIImage>()
    private let livePhotoCache = NSCache<NSString, PHLivePhoto>()
    // Use a real PHCachingImageManager instance so caching APIs are available.
    private let imageManager = PHCachingImageManager()
    private let imageLoadTimeout: TimeInterval = 10.0
    private let videoLoadTimeout: TimeInterval = 30.0
    private let livePhotoLoadTimeout: TimeInterval = 15.0
    private var isPhotoLibraryAvailable: Bool {
        UIApplication.shared.applicationState == .active
    }

    private lazy var thumbnailRequestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return options
    }()

    private init() {
        imageCache.countLimit = 30
        livePhotoCache.countLimit = 12
    }

    // MARK: - Public API

    func loadThumbnail(from assetIdentifier: String, key: String) async -> UIImage? {
        await loadImageWithCache(assetIdentifier: assetIdentifier, key: key, targetSize: Self.thumbnailSize)
    }

    func loadOriginalImage(from assetIdentifier: String, key: String, targetSize: CGSize = PHImageManagerMaximumSize) async -> UIImage? {
        await loadImageWithCache(assetIdentifier: assetIdentifier, key: key, targetSize: targetSize)
    }

    func loadFullImage(from assetIdentifier: String, key: String) async -> UIImage? {
        await loadImageWithCache(assetIdentifier: assetIdentifier, key: key, targetSize: Self.detailMaxSize)
    }

    func loadLivePhoto(from assetIdentifier: String, key: String, isOriginal: Bool = false) async -> PHLivePhoto? {
        if let cached = livePhotoCache.object(forKey: key as NSString) {
            return cached
        }

        guard let asset = fetchAsset(for: assetIdentifier),
              asset.mediaSubtypes.contains(.photoLive)
        else { return nil }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = isOriginal ? .original : .current

        let targetSize = isOriginal ? PHImageManagerMaximumSize : Self.detailMaxSize

        let livePhoto: PHLivePhoto? = await performRequest(tag: "LivePhoto", identifier: assetIdentifier, timeout: livePhotoLoadTimeout) { requestID, completion in
            requestID.value = PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { photo, info in
                // Skip low-quality previews and wait for high-quality results.
                if info?[PHImageResultIsDegradedKey] as? Bool == true,
                   photo != nil,
                   info?[PHImageCancelledKey] as? Bool != true,
                   info?[PHImageErrorKey] == nil
                {
                    return
                }
                completion(photo)
            }
        }

        if let livePhoto {
            livePhotoCache.setObject(livePhoto, forKey: key as NSString)
        }
        return livePhoto
    }

    func loadVideoURL(from assetIdentifier: String, isOriginal: Bool = false) async -> URL? {
        guard let asset = fetchAsset(for: assetIdentifier)
        else { return nil }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = isOriginal ? .original : .current

        return await performRequest(tag: "Video", identifier: assetIdentifier, timeout: videoLoadTimeout) { requestID, completion in
            requestID.value = self.imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                completion((avAsset as? AVURLAsset)?.url)
            }
        }
    }

    // MARK: - Cache Management

    func getCachedImage(for key: String) -> UIImage? {
        imageCache.object(forKey: key as NSString)
    }

    func getCachedLivePhoto(for key: String) -> PHLivePhoto? {
        livePhotoCache.object(forKey: key as NSString)
    }

    func clearCache() {
        stopCachingAllImages()
        imageCache.removeAllObjects()
        livePhotoCache.removeAllObjects()
    }

    // MARK: - Thumbnail Prefetch

    func startCachingThumbnails(for assetIdentifiers: [String]) {
        guard !assetIdentifiers.isEmpty else { return }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: Self.thumbnailSize,
            contentMode: .aspectFit,
            options: thumbnailRequestOptions
        )
    }

    func stopCachingAllImages() {
        imageManager.stopCachingImagesForAllAssets()
    }

    func removeCache(for key: String) {
        let hadImage = imageCache.object(forKey: key as NSString) != nil
        let hadLivePhoto = livePhotoCache.object(forKey: key as NSString) != nil

        imageCache.removeObject(forKey: key as NSString)
        livePhotoCache.removeObject(forKey: key as NSString)

        print("🗑️ PhotoLoader.removeCache: key: \(key)，删除图片缓存: \(hadImage)，删除LivePhoto缓存: \(hadLivePhoto)")
    }

    func assetExists(_ assetIdentifier: String) -> Bool {
        fetchAsset(for: assetIdentifier) != nil
    }

    /// Avoid doing synchronous Photos fetches on the main thread.
    func assetExistsAsync(_ assetIdentifier: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject != nil
        }.value
    }

    // MARK: - Private Helpers

    private func fetchAsset(for identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private func loadImageWithCache(assetIdentifier: String, key: String, targetSize: CGSize) async -> UIImage? {
        print("🔍 PhotoLoader.loadImageWithCache开始: key: \(key)，targetSize: \(targetSize)，assetIdentifier: \(assetIdentifier)")

        if let cached = imageCache.object(forKey: key as NSString) {
            print("✅ PhotoLoader.loadImageWithCache: 缓存命中，key: \(key)")
            return cached
        }

        print("⚡ PhotoLoader.loadImageWithCache: 缓存未命中，开始加载...")
        guard let asset = fetchAsset(for: assetIdentifier) else {
            print("❌ PhotoLoader.loadImageWithCache: 资产不存在，key: \(key)，assetIdentifier: \(assetIdentifier)")
            return nil
        }

        print("✅ PhotoLoader.loadImageWithCache: 资产存在，开始PHImageManager请求，key: \(key)")

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        let image: UIImage? = await performRequest(tag: "Image", identifier: assetIdentifier, timeout: imageLoadTimeout) { requestID, completion in
            requestID.value = self.imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // Skip low-quality previews and wait for high-quality results.
                if info?[PHImageResultIsDegradedKey] as? Bool == true,
                   image != nil,
                   info?[PHImageCancelledKey] as? Bool != true,
                   info?[PHImageErrorKey] == nil
                {
                    return
                }
                completion(image)
            }
        }

        if let image {
            imageCache.setObject(image, forKey: key as NSString)
            print("✅ PhotoLoader.loadImageWithCache: 图片加载成功并缓存，key: \(key)")
        } else {
            print("❌ PhotoLoader.loadImageWithCache: 图片加载失败，key: \(key)")
        }
        return image
    }

    /// Unified handling for `PHImageManager` requests with timeout and cancellation support.
    private func performRequest<T>(
        tag: String,
        identifier: String,
        timeout: TimeInterval,
        request: @escaping (RequestID, @escaping (T?) -> Void) -> Void
    ) async -> T? {
        let requestID = RequestID()
        print("⏰ PhotoLoader.performRequest开始: tag: \(tag)，identifier: \(identifier)，timeout: \(timeout)s")

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Thread-safe single resume using actor isolation.
                let state = ContinuationState(continuation: continuation)

                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if await state.tryResume(with: nil) {
                        requestID.cancel(with: imageManager)
                        print("⏱️ PhotoLoader.performRequest超时: tag: \(tag)，identifier: \(identifier)，超时时间: \(timeout)s")
                    }
                }

                request(requestID) { result in
                    Task {
                        if await state.tryResume(with: result) {
                            timeoutTask.cancel()
                            if result != nil {
                                print("✅ PhotoLoader.performRequest成功: tag: \(tag)，identifier: \(identifier)")
                            } else {
                                print("❌ PhotoLoader.performRequest失败: tag: \(tag)，identifier: \(identifier)")
                            }
                        }
                    }
                }

                // Handle requests canceled before they are initiated.
                if Task.isCancelled {
                    Task {
                        if await state.tryResume(with: nil) {
                            timeoutTask.cancel()
                            requestID.cancel(with: imageManager)
                            print("❌ PhotoLoader.performRequest请求前取消: tag: \(tag)，identifier: \(identifier)")
                        }
                    }
                }
            }
        } onCancel: {
            requestID.cancel(with: imageManager)
            print("❌ PhotoLoader.performRequest被取消: tag: \(tag)，identifier: \(identifier)")
        }
    }
}

// MARK: - Helper Types

private final class RequestID: @unchecked Sendable {
    var value: PHImageRequestID?

    func cancel(with manager: PHImageManager) {
        if let id = value {
            manager.cancelImageRequest(id)
        }
    }
}

private actor ContinuationState<T> {
    private var continuation: CheckedContinuation<T?, Never>?

    init(continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func tryResume(with value: T?) -> Bool {
        guard let cont = continuation else { return false }
        continuation = nil
        cont.resume(returning: value)
        return true
    }
}

struct AsyncThumbnailImage: View {
    let assetIdentifier: String
    let photoId: String

    @State private var loadedImage: UIImage?
    @State private var loadState: LoadState = .loading
    @State private var retryCount = 0

    private enum LoadState {
        case loading, success, failed, notFound
    }

    private let imageCache = PhotoLoader.shared
    private let maxRetries = 2

    private var placeholderColor: Color {
        Color(red: 0.12, green: 0.12, blue: 0.12)
    }

    /// Reload when either `photoId` or `assetIdentifier` changes.
    private var loadKey: String {
        "\(photoId)_\(assetIdentifier)"
    }

    @ViewBuilder
    private func placeholderView(icon systemName: String? = nil) -> some View {
        placeholderColor
            .overlay(
                Group {
                    if let name = systemName {
                        Image(systemName: name)
                            .foregroundColor(.gray)
                            .font(.system(size: 18))
                    } else {
                        EmptyView()
                    }
                }
            )
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                switch loadState {
                case .loading:
                    placeholderView()
                case .notFound:
                    placeholderView(icon: "exclamationmark.magnifyingglass")
                case .failed:
                    placeholderView(icon: "exclamationmark.triangle")
                        .onTapGesture {
                            if retryCount < maxRetries {
                                retryCount += 1
                                Task { await loadImage() }
                            }
                        }
                case .success:
                    placeholderView()
                }
            }
        }
        .task(id: loadKey) {
            await loadImage()
        }
    }

    private func loadImage() async {
        await MainActor.run {
            loadState = .loading
            loadedImage = nil
        }

        if Task.isCancelled { return }

        // Load the thumbnail directly first to avoid an extra asset existence check.
        let image = await imageCache.loadThumbnail(from: assetIdentifier, key: photoId)

        if Task.isCancelled { return }

        await MainActor.run {
            if let image {
                loadedImage = image
                loadState = .success
            } else {
                // If loading fails, check whether the resource exists to distinguish the error type.
                let exists = imageCache.assetExists(assetIdentifier)
                loadState = exists ? .failed : .notFound
            }
        }
    }
}
