import AVFoundation
import AVKit
import Photos
import SwiftUI

struct PhotoPreviewView: View {
    let photos: [PhotoAsset]
    @Binding var selectedIndex: Int
    @Binding var showingOriginal: Bool
    @ObservedObject var videoControls: VideoControls
    @ObservedObject var livePhotoControls: LivePhotoControls
    @ObservedObject var frameManager: FrameManager
    var onSingleTap: (() -> Void)?

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(
                Array(photos.enumerated()),
                id: \.element.id
            ) { idx, photo in
                AsyncPhotoView(
                    photo: photo,
                    isActive: selectedIndex == idx,
                    showingOriginal: showingOriginal && selectedIndex == idx,
                    videoControls: videoControls,
                    livePhotoControls: livePhotoControls,
                    frameManager: frameManager,
                    onSingleTap: onSingleTap
                )
                .tag(idx)
                .ignoresSafeArea()
                .onAppear {
                    print("📸 PhotoPreviewView: 选中索引 \(idx)，照片ID: \(photo.id.uuidString.prefix(8))，总照片数: \(photos.count)")
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .onChange(of: selectedIndex) { oldValue, newValue in
            print("🔄 PhotoPreviewView: 索引从 \(oldValue) 变化到 \(newValue)，当前照片数: \(photos.count)")
            if newValue < photos.count {
                let currentPhotoId = photos[newValue].id.uuidString.prefix(8)
                let isActive = oldValue == newValue ? "相同" : "不同"
                print("📍 PhotoPreviewView: 当前选中照片 \(currentPhotoId)，索引变化类型: \(isActive)")
            }
        }
    }
}

struct AsyncPhotoView: View {
    let photo: PhotoAsset
    let isActive: Bool
    let showingOriginal: Bool
    @ObservedObject var videoControls: VideoControls
    @ObservedObject var livePhotoControls: LivePhotoControls
    @ObservedObject var frameManager: FrameManager
    var onSingleTap: (() -> Void)?

    @State private var loadedImage: UIImage?
    @State private var framedImage: UIImage?
    @State private var loadedLivePhoto: PHLivePhoto?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    @State private var isVideo = false
    @State private var isLivePhoto = false
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var loadError = false

    private var targetAssetId: String {
        showingOriginal ? (photo.originalAssetIdentifier ?? photo.assetIdentifier) : photo.assetIdentifier
    }

    private var originalAvailable: Bool { showingOriginal && photo.originalAssetIdentifier != nil }
    private var imageKeyOriginal: String { "\(photo.id.uuidString)_original_preview" }
    private var imageKeyFull: String { "\(photo.id.uuidString)_full" }
    private var liveKeyOriginal: String { "\(photo.id.uuidString)_original_live" }
    private var liveKeyFull: String { "\(photo.id.uuidString)_live" }

    var body: some View {
        ZStack {
            PhotoZoomableViewRepresentable(
                image: framedImage ?? loadedImage,
                livePhoto: loadedLivePhoto,
                player: player,
                videoControls: isVideo ? videoControls : nil,
                livePhotoControls: isLivePhoto ? livePhotoControls : nil,
                isVisible: isActive,
                onSingleTap: onSingleTap
            )

            if isLoading {
                Color.black
                    .overlay(
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                    )
            }

            if loadError {
                Color.black
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.6))
                            Text(String.photoPreviewLoadFailed.localized)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                            Button(String.photoPreviewRetry.localized) {
                                print("🔄 用户点击重试按钮，照片ID: \(photo.id.uuidString.prefix(8))，isActive: \(isActive)，showingOriginal: \(showingOriginal)")
                                loadTask?.cancel()
                                loadTask = Task { await loadImage() }
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.8))
                        }
                    )
            }
        }
        .task {
            print("🚀 AsyncPhotoView.task: 开始加载照片ID: \(photo.id.uuidString.prefix(8))，isActive: \(isActive)，showingOriginal: \(showingOriginal)")
            await loadImage()
        }
        .onChange(of: isActive) { oldValue, newValue in
            handleIsActiveChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: showingOriginal) { oldValue, newValue in
            print("🔄 AsyncPhotoView.showingOriginal变化: 照片ID: \(photo.id.uuidString.prefix(8))，从 \(oldValue) 到 \(newValue)，isActive: \(isActive)")
            loadTask?.cancel()
            loadTask = Task { await loadImage() }
        }
        .onChange(of: loadedImage) { oldValue, newValue in
            print("📷 AsyncPhotoView.loadedImage变化: 照片ID: \(photo.id.uuidString.prefix(8))，从 \(oldValue != nil) 到 \(newValue != nil)，isActive: \(isActive)")
        }
        .onChange(of: frameManager.isFrameOn) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.currentTemplate) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showEXIFInfo) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showAppleIcon) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showDeviceModel) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showDate) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showTime) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showLocation) { _, isShown in
            if isShown {
                enrichMetadataIfNeeded()
            }
            updateFramedImage()
        }
        .onChange(of: frameManager.showCopyright) { _, _ in updateFramedImage() }
        .onChange(of: frameManager.showFestivalWatermark) { _, _ in updateFramedImage() }
        .onChange(of: photo.metadata) { _, _ in updateFramedImage() }
        .onDisappear {
            handleDisappear()
        }
    }

    private func handleIsActiveChange(oldValue: Bool, newValue: Bool) {
        print("🔄 AsyncPhotoView.isActive变化: 照片ID: \(photo.id.uuidString.prefix(8))，从 \(oldValue) 到 \(newValue)，loadedImage: \(loadedImage != nil)")
        if !newValue {
            if isVideo {
                player?.pause()
                print("⏸️ AsyncPhotoView: 暂停视频播放，照片ID: \(photo.id.uuidString.prefix(8))")
            }
        } else {
            if isVideo, videoControls.isPlaying {
                player?.play()
                print("▶️ AsyncPhotoView: 恢复视频播放，照片ID: \(photo.id.uuidString.prefix(8))")
            }
        }
    }

    private func handleDisappear() {
        print("👋 AsyncPhotoView.onDisappear: 照片ID: \(photo.id.uuidString.prefix(8))，isActive: \(isActive)，loadedImage: \(loadedImage != nil)，loadError: \(loadError)")
        loadTask?.cancel()
        if isVideo {
            player?.pause()
            player = nil
            playerItem = nil
            print("👋 AsyncPhotoView: 清理视频资源，照片ID: \(photo.id.uuidString.prefix(8))")
        }
        if isLivePhoto {
            loadedLivePhoto = nil
        }
    }

    @MainActor
    private func finishLoading(image: UIImage? = nil, live: PHLivePhoto? = nil, error: Bool = false) {
        print("✅ AsyncPhotoView.finishLoading: 照片ID: \(photo.id.uuidString.prefix(8))，isActive: \(isActive)，image: \(image != nil)，live: \(live != nil)，error: \(error)")

        loadedImage = image
        loadedLivePhoto = live
        isLoading = false
        loadError = error

        // After loading completes, check whether the location name should be enriched.
        if frameManager.isEnabled, frameManager.showLocation, !error {
            enrichMetadataIfNeeded()
        }
    }

    private func enrichMetadataIfNeeded() {
        Task {
            await photo.enrichLocationNameIfNeeded()
        }
    }

    private func updateFramedImage() {
        guard let image = loadedImage else {
            framedImage = nil
            return
        }

        // Photo frames are not applied to videos and Live Photos.
        if isVideo || isLivePhoto {
            framedImage = nil
            return
        }

        if frameManager.isEnabled {
            Task {
                let metadata = DictionarySerializer.decodeDictionaryFromData(
                    photo.metadata ?? Data()
                )
                let result = frameManager.applyFrameToImage(
                    image,
                    metadata: metadata
                )
                await MainActor.run {
                    framedImage = result
                }
            }
        } else {
            framedImage = nil
        }
    }

    private func loadImage() async {
        print("🔍 AsyncPhotoView.loadImage开始: 照片ID: \(photo.id.uuidString.prefix(8))，targetAssetId: \(targetAssetId)，isActive: \(isActive)，originalAvailable: \(originalAvailable)")

        if loadedImage == nil, loadedLivePhoto == nil, player == nil {
            await MainActor.run {
                isLoading = true
                loadError = false
                print("🔄 AsyncPhotoView.loadImage: 重置加载状态为isLoading=true, loadError=false")
            }
        } else {
            print("⚡ AsyncPhotoView.loadImage: 跳过状态重置，当前状态 - loadedImage: \(loadedImage != nil)，loadedLivePhoto: \(loadedLivePhoto != nil)，player: \(player != nil)")
        }

        let isVideoAsset = await photo.isVideo(for: targetAssetId)
        let isLive = await photo.isLivePhoto(for: targetAssetId)

        print("🎬 AsyncPhotoView.loadImage: 检测媒体类型 - isVideo: \(isVideoAsset)，isLive: \(isLive)")

        await MainActor.run {
            isVideo = isVideoAsset
            isLivePhoto = isLive && !isVideoAsset
        }

        if isVideoAsset {
            print("🎥 AsyncPhotoView.loadImage: 开始加载视频，targetAssetId: \(targetAssetId)")
            let videoURL = await PhotoLoader.shared.loadVideoURL(from: targetAssetId, isOriginal: originalAvailable)
            await MainActor.run {
                if let url = videoURL {
                    print("✅ AsyncPhotoView.loadImage: 视频URL加载成功，照片ID: \(photo.id.uuidString.prefix(8))")
                    playerItem = AVPlayerItem(url: url)
                    player = AVPlayer(playerItem: playerItem)

                    // Update available playback rates based on video capabilities
                    videoControls.updateAvailableRates(for: playerItem)

                    player?.rate = videoControls.playbackRate
                    player?.isMuted = videoControls.isMuted
                    if videoControls.isPlaying { player?.play() }
                    loadError = false
                } else {
                    // Video loading failed
                    print("❌ AsyncPhotoView.loadImage: 视频URL加载失败，照片ID: \(photo.id.uuidString.prefix(8))，targetAssetId: \(targetAssetId)")
                    loadError = true
                }
                isLoading = false
            }
            return
        }

        if isLive {
            print("📸 AsyncPhotoView.loadImage: 开始加载LivePhoto，targetAssetId: \(targetAssetId)")
            let liveKey = showingOriginal ? liveKeyOriginal : liveKeyFull
            if let cachedLive = PhotoLoader.shared.getCachedLivePhoto(for: liveKey) {
                print("✅ AsyncPhotoView.loadImage: 从缓存加载LivePhoto，照片ID: \(photo.id.uuidString.prefix(8))，key: \(liveKey)")
                finishLoading(image: nil, live: cachedLive)
                return
            }

            let livePhoto = await PhotoLoader.shared.loadLivePhoto(from: targetAssetId, key: liveKey, isOriginal: originalAvailable)
            if let livePhoto {
                print("✅ AsyncPhotoView.loadImage: LivePhoto加载成功，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: nil, live: livePhoto)
                return
            } else {
                print("⚠️ AsyncPhotoView.loadImage: LivePhoto加载失败，回退到静态图，照片ID: \(photo.id.uuidString.prefix(8))")
            }
            // Fall back to a static image.
        }

        if showingOriginal {
            print("🖼️ AsyncPhotoView.loadImage: 加载原图，照片ID: \(photo.id.uuidString.prefix(8))，key: \(imageKeyOriginal)")
            if let cached = PhotoLoader.shared.getCachedImage(for: imageKeyOriginal) {
                print("✅ AsyncPhotoView.loadImage: 从缓存加载原图，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: cached, live: nil)
                return
            }
            print("🔍 AsyncPhotoView.loadImage: 缓存未命中，开始加载原图...")
            let image = await photo.loadOriginalImage(
                targetSize: PhotoLoader.detailMaxSize,
                cacheKeySuffix: "original_preview"
            )
            if image != nil {
                print("✅ AsyncPhotoView.loadImage: 原图加载成功，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: image, live: nil)
            } else {
                print("❌ AsyncPhotoView.loadImage: 原图加载失败，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: nil, live: nil, error: true)
            }
        } else {
            print("🖼️ AsyncPhotoView.loadImage: 加载全图，照片ID: \(photo.id.uuidString.prefix(8))，key: \(imageKeyFull)")
            if let cached = PhotoLoader.shared.getCachedImage(for: imageKeyFull) {
                print("✅ AsyncPhotoView.loadImage: 从缓存加载全图，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: cached, live: nil)
                return
            }
            print("🔍 AsyncPhotoView.loadImage: 缓存未命中，开始加载全图...")
            let image = await photo.loadFullImage()
            if image != nil {
                print("✅ AsyncPhotoView.loadImage: 全图加载成功，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: image, live: nil)
            } else {
                print("❌ AsyncPhotoView.loadImage: 全图加载失败，照片ID: \(photo.id.uuidString.prefix(8))")
                finishLoading(image: nil, live: nil, error: true)
            }
        }
    }
}
