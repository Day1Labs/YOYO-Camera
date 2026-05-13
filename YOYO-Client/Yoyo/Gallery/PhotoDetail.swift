import AVFoundation
import LinkPresentation
import Photos
import SwiftUI
import UIKit

final class VideoControls: ObservableObject {
    @Published var isPlaying: Bool = true
    @Published var playbackRate: Float = 1.0
    @Published var isMuted: Bool = true
    @Published var availableRates: [Float] = [1.0, 2.0, 3.0, 6.0]

    private var availableRatesTask: Task<Void, Never>?

    func cyclePlaybackRate() {
        if let currentIndex = availableRates.firstIndex(of: playbackRate) {
            let nextIndex = (currentIndex + 1) % availableRates.count
            playbackRate = availableRates[nextIndex]
        } else {
            playbackRate = availableRates.first ?? 1.0
        }
    }

    func updateAvailableRates(for playerItem: AVPlayerItem?) {
        availableRatesTask?.cancel()

        guard let playerItem else {
            availableRates = [1.0]
            playbackRate = 1.0
            return
        }

        availableRatesTask = Task {
            let maxRate = await VideoPlaybackCapability.calculateMaxPlaybackRate(for: playerItem)
            let newRates = VideoPlaybackCapability.generatePlaybackRates(maxRate: maxRate)

            await MainActor.run {
                availableRates = newRates

                // Reset playback rate to 1.0 if current rate exceeds max
                if playbackRate > maxRate {
                    playbackRate = 1.0
                }
            }
        }
    }
}

final class LivePhotoControls: ObservableObject {
    @Published var isPlaying: Bool = true
    @Published var isLooping: Bool = false
    @Published var playbackTrigger: Int = 0
}

struct PhotoDetailView: View {
    var photos: [PhotoAsset]
    @State var currentIndex: Int
    var onPhotoDeleted: (() -> Void)? // Photo delete callback
    var onBackToCamera: (() -> Void)? // Return to camera callback
    var onDismissOverride: (() -> Void)?
    @State private var localPhotos: [PhotoAsset] = [] // Local photo array for update after deletion
    @State private var showingOriginal = false
    @State private var isLongPressing = false
    @State private var pressStartTime: Date?
    @State private var shareItem: ShareablePhotoItem?
    @State private var hasOriginal = false
    @State private var showingInfoSheet = false // Show information panel
    @State private var showingControls = true // Control showing and hiding top/bottom panels
    @StateObject private var videoControls = VideoControls() // Video playback control status
    @State private var isCurrentVideo = false // Is the current video
    @State private var isCurrentLivePhoto = false // Is the current LivePhoto
    @StateObject private var livePhotoControls = LivePhotoControls() // LivePhoto playback control status
    @ObservedObject private var frameManager = FrameManager.shared // Photo frame manager
    @State private var showingFrameSettings = false // Show frame settings
    @State private var showingAIPanel = false // Show AI function panel
    @State private var isProcessingAI = false // AI processing
    @State private var isSaved = false // Save successful status
    @State private var statusRefreshTask: Task<Void, Never>?
    @State private var originalPrefetchTask: Task<Void, Never>?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var permissionManager: PermissionManager // New: Permission Manager
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var sideButtonSize: CGFloat {
        isSmallScreen ? 40 : 48
    }

    private var centerButtonWidth: CGFloat {
        isSmallScreen ? 38 : 44
    }

    private var horizontalPadding: CGFloat {
        isSmallScreen ? 12 : 20
    }

    /// Use safe access to prevent index out-of-bounds crashes after deletion.
    private var photo: PhotoAsset? {
        guard localPhotos.indices.contains(currentIndex) else { return nil }
        return localPhotos[currentIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background content: photo carousel.
                PhotoPreviewView(
                    photos: localPhotos,
                    selectedIndex: $currentIndex,
                    showingOriginal: $showingOriginal,
                    videoControls: videoControls,
                    livePhotoControls: livePhotoControls,
                    frameManager: frameManager,
                    onSingleTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingControls.toggle()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingControls.toggle()
                    }
                }

                // Floating top and bottom panels.
                VStack {
                    // Top navigation bar.
                    if showingControls {
                        navigationBar()
                            .padding(.top, geometry.safeAreaInsets.top)
                            .padding(.horizontal, horizontalPadding)
                    }

                    Spacer()

                    // Bottom information panel.
                    if showingControls {
                        if showingAIPanel {
                            AIDarkroomPanelView(
                                showingAIPanel: $showingAIPanel,
                                isProcessingAI: $isProcessingAI,
                                isSaved: $isSaved,
                                currentIndex: $currentIndex,
                                localPhotos: $localPhotos,
                                photo: photo
                            )
                            .padding(.bottom, geometry.safeAreaInsets.bottom)
                            .padding(.horizontal, horizontalPadding)
                        } else {
                            // Floating buttons: AI on the left, compare on the right.
                            HStack {
                                // AI Button (Left)
                                if !isCurrentVideo, !isCurrentLivePhoto {
                                    AIDarkroomButton(showingAIPanel: $showingAIPanel, sideButtonSize: sideButtonSize)
                                        .padding(.leading, horizontalPadding)
                                        .padding(.bottom, 12)
                                }

                                Spacer()

                                // Compare button.
                                if hasOriginal {
                                    contrastButton()
                                        .padding(.trailing, horizontalPadding)
                                        .padding(.bottom, 12)
                                }
                            }

                            bottomInfoPanel()
                                .padding(.bottom, geometry.safeAreaInsets.bottom)
                                .padding(.horizontal, horizontalPadding)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
            .edgesIgnoringSafeArea(.all)

            // AI Loading Overlay
            if isProcessingAI {
                AIDarkroomLoadingOverlay()
            }
        }
        .buttonStyle(.plain)
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .task {
            print("🚀 PhotoDetailView.task初始化: 接收照片数: \(photos.count)，初始索引: \(currentIndex)")
            localPhotos = photos
            scheduleStatusRefresh(for: currentIndex)
            print("📸 PhotoDetailView.task初始化完成: localPhotos.count: \(localPhotos.count)")
        }
        .onChange(of: currentIndex) { oldValue, newIndex in
            print("🔄 PhotoDetailView.currentIndex变化: 从 \(oldValue) 到 \(newIndex)，localPhotos.count: \(localPhotos.count)")
            scheduleStatusRefresh(for: newIndex)
        }
        .onChange(of: showingOriginal) { _, _ in
            scheduleStatusRefresh(for: currentIndex)
        }
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: [item])
        }
        .sheet(isPresented: $showingInfoSheet) {
            PhotoInfoView(photo: photo)
                .presentationDetents([.height(410)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFrameSettings) {
            FrameSettingsView(frameManager: frameManager)
                .presentationDetents([.height(450)])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            statusRefreshTask?.cancel()
            originalPrefetchTask?.cancel()
        }
        .trackScreen(name: "PhotoDetail")
    }

    // MARK: - Navigation bar
    private func navigationBar() -> some View {
        HStack {
            Button(
                action: {
                    performHaptic()
                    if let onDismissOverride { onDismissOverride() } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: sideButtonSize, height: sideButtonSize)
                        .glassCardStyle(cornerRadius: sideButtonSize / 2)
                }
            Spacer()
            VStack(spacing: 2) {
                // Shooting time information.
                if let ts = photo?.timestamp {
                    Text(formattedTimestamp(for: ts))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text("")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }

                Text(
                    showingOriginal ? String.photoDetailOriginal.localized : {
                        if let filterIdentifier = photo?.filterIdentifier {
                            "#" + FilterConfigManager
                                .getFilterDisplayName(for: filterIdentifier)
                        } else if let rawValue = photo?.filterName, !rawValue.isEmpty {
                            "#" + rawValue
                        } else {
                            ""
                        }
                    }()
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            }

            Spacer()

            Menu {
                Button(action: {
                    performHaptic(style: .medium)
                    toggleFavorite()
                }) {
                    let isFav = photo?.isFavorite ?? false
                    Label(isFav ? String.photoDetailUnfavorite.localized : String.photoDetailFavorite.localized,
                          systemImage: isFav ? "heart.slash" : "heart")
                }

                Button(action: {
                    performHaptic()
                    sharePhoto()
                }) {
                    Label(
                        String.photoDetailShare.localized,
                        systemImage: "square.and.arrow.up"
                    )
                }

                Button(action: {
                    performHaptic()
                    openInPhotos()
                }) {
                    Label(
                        String.photoDetailOpenInPhotos.localized,
                        systemImage: "photo.on.rectangle.angled"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: sideButtonSize, height: sideButtonSize)
                    .glassCardStyle(cornerRadius: sideButtonSize / 2)
            }
        }
        .compositingGroup()
    }

    // MARK: - Bottom information panel
    private func bottomInfoPanel() -> some View {
        HStack(spacing: 0) {
            // Left: back-to-camera button.
            Button(action: {
                performHaptic()
                dismiss()
                onBackToCamera?()
            }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: sideButtonSize, height: sideButtonSize)
                    .glassCardStyle(cornerRadius: sideButtonSize / 2)
            }

            Spacer()

            // Middle: operation button group.
            HStack(spacing: 0) {
                // Favorite button.
                Button(action: {
                    performHaptic(style: .medium)
                    toggleFavorite()
                }) {
                    Image(
                        systemName: (
                            photo?.isFavorite ?? false
                        ) ? "heart.fill" : "heart"
                    )
                    .font(.system(size: 20))
                    .foregroundColor(
                        (photo?.isFavorite ?? false) ? .red : .white
                            .opacity(0.8)
                    )
                    .frame(width: centerButtonWidth, height: sideButtonSize)
                }

                // Info button.
                Button(action: {
                    performHaptic()
                    showingInfoSheet = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: centerButtonWidth, height: sideButtonSize)
                }

                // Photo frame button, only shown for still photos.
                if !isCurrentVideo, !isCurrentLivePhoto {
                    Button(action: {
                        performHaptic()
                        showingFrameSettings = true
                    }) {
                        Image(systemName: "square.bottomthird.inset.filled")
                            .font(.system(size: 20))
                            .foregroundColor(
                                frameManager.isEnabled ? .accentColor : .white
                                    .opacity(0.8)
                            )
                            .frame(width: centerButtonWidth, height: sideButtonSize)
                    }

                    // Save button, only shown when the frame feature is enabled.
                    if frameManager.isEnabled {
                        Button(action: {
                            performHaptic()
                            saveWithFrame()
                        }) {
                            Image(systemName: isSaved ? "checkmark" : "square.and.arrow.down")
                                .font(.system(size: 20))
                                .foregroundColor(isSaved ? .green : .white.opacity(0.8))
                                .frame(width: centerButtonWidth, height: sideButtonSize)
                                .offset(y: isSaved ? 0 : -2)
                        }
                        .disabled(isSaved)
                    }
                }

                // Video controls.
                if isCurrentVideo {
                    // Play / pause button.
                    Button(action: {
                        performHaptic()
                        togglePlayPause()
                    }) {
                        Image(
                            systemName: videoControls.isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: centerButtonWidth, height: sideButtonSize)
                    }

                    // Playback rate button.
                    Button(action: {
                        performHaptic()
                        cyclePlaybackRate()
                    }) {
                        Text("\(videoControls.playbackRate.clean)x")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: centerButtonWidth, height: sideButtonSize)
                    }

                    // Mute toggle button.
                    Button(action: {
                        performHaptic()
                        toggleMute()
                    }) {
                        Image(
                            systemName: videoControls.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                        )
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: centerButtonWidth, height: sideButtonSize)
                    }
                }

                // Live Photo controls.
                if isCurrentLivePhoto {
                    Button(action: {
                        performHaptic()
                        playLivePhoto()
                    }) {
                        Image(systemName: "livephoto.play")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: centerButtonWidth, height: sideButtonSize)
                    }
                }
            }
            .padding(.horizontal, 4)
            .glassCardStyle(cornerRadius: 25)

            Spacer()

            // Right: delete button.
            Button(action: {
                performHaptic(style: .medium)
                deletePhoto()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: sideButtonSize, height: sideButtonSize)
                    .glassCardStyle(cornerRadius: sideButtonSize / 2)
            }
        }
        .compositingGroup()
    }

    private func contrastButton() -> some View {
        Image(
            // systemName: showingOriginal ? "rectangle.leadinghalf.filled" : "rectangle.trailinghalf.filled"
            systemName: "arrow.right.arrow.left"
        )
        .font(.system(size: 20))
        .foregroundColor(.white.opacity(0.8))
        .frame(width: sideButtonSize, height: sideButtonSize)
        .glassCardStyle(cornerRadius: sideButtonSize / 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isLongPressing {
                        isLongPressing = true
                        pressStartTime = Date()
                        toggleOriginalWithHaptic()
                    }
                }
                .onEnded { _ in
                    isLongPressing = false
                    if let startTime = pressStartTime {
                        let duration = Date().timeIntervalSince(startTime)
                        if duration > 0.2 {
                            toggleOriginalWithHaptic()
                        }
                        pressStartTime = nil
                    }
                }
        )
    }

    private func formattedTimestamp(for date: Date) -> String {
        let locale = LanguageManager.shared.locale
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute().locale(locale))
        } else if Calendar.current.isDateInYesterday(date) {
            return String.timeYesterday.localized
        } else {
            return date.formatted(.relative(presentation: .named).locale(locale))
        }
    }

    // MARK: - Helper Methods

    private func toggleFavorite() {
        guard let photo else { return }

        // Check permissions.
        guard permissionManager.hasPhotoLibraryPermission else {
            permissionManager.checkPhotoLibraryPermission()
            return
        }

        let newStatus = !photo.isFavorite
        AnalyticsManager.shared.log(.galleryAction(action: "favorite"))
        // Optimistically update the UI.
        photo.isFavorite = newStatus

        Task {
            do {
                // Sync to the system album.
                try await PhotoAlbumManager.shared.toggleFavorite(for: photo.assetIdentifier, isFavorite: newStatus)

                // If the original image exists, try to sync it too.
                if let originalId = photo.originalAssetIdentifier {
                    try? await PhotoAlbumManager.shared.toggleFavorite(for: originalId, isFavorite: newStatus)
                }
            } catch {
                print("Failed to toggle favorite in system library: \(error)")
                // Roll back on failure.
                await MainActor.run {
                    photo.isFavorite = !newStatus
                }
            }
        }
    }

    private func saveWithFrame() {
        guard let targetPhoto = photo else { return }

        // Check permissions.
        guard permissionManager.hasPhotoLibraryPermission else {
            permissionManager.checkPhotoLibraryPermission()
            return
        }

        AnalyticsManager.shared.log(.galleryAction(action: "quick_save"))

        Task {
            let shouldShareOriginal = showingOriginal
            let image: UIImage?
            if shouldShareOriginal {
                image = await targetPhoto.loadOriginalImage()
            } else {
                image = await targetPhoto.loadFullImage()
            }
            guard let baseImage = image else { return }

            let finalImage: UIImage
            // Only apply frames when the asset is neither video nor Live Photo.
            if frameManager.isEnabled, !isCurrentVideo, !isCurrentLivePhoto {
                let metadata = DictionarySerializer.decodeDictionaryFromData(
                    targetPhoto.metadata ?? Data()
                )
                finalImage = frameManager
                    .applyFrameToImage(
                        baseImage,
                        metadata: metadata
                    ) ?? baseImage
            } else {
                finalImage = baseImage
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: finalImage)
                }

                await MainActor.run {
                    performHaptic(style: .medium)
                    withAnimation {
                        isSaved = true
                    }
                }

                // Reset status after 2 seconds.
                try await Task.sleep(nanoseconds: 2 * 1_000_000_000)

                await MainActor.run {
                    withAnimation {
                        isSaved = false
                    }
                }
            } catch {
                print("Failed to save image: \(error)")
            }
        }
    }

    private func togglePlayPause() {
        videoControls.isPlaying.toggle()
    }

    private func cyclePlaybackRate() {
        videoControls.cyclePlaybackRate()
    }

    private func toggleMute() {
        videoControls.isMuted.toggle()
    }

    private func playLivePhoto() {
        livePhotoControls.isPlaying = true
        livePhotoControls.playbackTrigger += 1
    }

    private func toggleOriginalWithHaptic() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingOriginal.toggle()
        }
        AnalyticsManager.shared.log(.galleryViewOriginal(isOriginal: showingOriginal))
        performHaptic()
    }

    private func performHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }

    private func sharePhoto() {
        AnalyticsManager.shared.log(.galleryAction(action: "share_start"))
        Task {
            guard let targetPhoto = photo else { return }
            let shouldShareOriginal = showingOriginal
            let image: UIImage?
            if shouldShareOriginal {
                image = await targetPhoto.loadOriginalImage()
            } else {
                image = await targetPhoto.loadFullImage()
            }
            guard let baseImage = image else { return }

            let finalImage: UIImage
            // Only apply frames when the asset is neither video nor Live Photo.
            if frameManager.isEnabled, !isCurrentVideo, !isCurrentLivePhoto {
                let metadata = DictionarySerializer.decodeDictionaryFromData(
                    targetPhoto.metadata ?? Data()
                )
                finalImage = frameManager
                    .applyFrameToImage(
                        baseImage,
                        metadata: metadata
                    ) ?? baseImage
            } else {
                finalImage = baseImage
            }

            await MainActor.run {
                shareItem = ShareablePhotoItem(
                    image: finalImage,
                    title: targetPhoto.title
                )
            }
        }
    }

    private func openInPhotos() {
        guard let photo else { return }
        let assetId = showingOriginal ? (
            photo.originalAssetIdentifier ?? photo.assetIdentifier
        ) : photo.assetIdentifier

        if let url = URL(string: "photos-redirect://asset/\(assetId)") {
            UIApplication.shared.open(url)
        }
    }

    private func deletePhoto() {
        if !permissionManager.hasPhotoLibraryPermission {
            permissionManager.checkPhotoLibraryPermission()
            guard permissionManager.hasPhotoLibraryPermission else { return }
        }

        guard let photoToDelete = photo else { return }
        AnalyticsManager.shared.log(.galleryAction(action: "delete_single"))

        print("🗑️ PhotoDetailView.deletePhoto开始: 删除照片ID: \(photoToDelete.id.uuidString.prefix(8))，当前索引: \(currentIndex)，总照片数: \(localPhotos.count)")

        Task {
            do {
                var assetIdentifiersToDelete = [photoToDelete.assetIdentifier]
                if let originalAssetId = photoToDelete.originalAssetIdentifier {
                    assetIdentifiersToDelete.append(originalAssetId)
                }

                print("🗑️ PhotoDetailView.deletePhoto: 准备删除资源标识符: \(assetIdentifiersToDelete)")

                try await PhotoAlbumManager.shared
                    .deletePhotosFromAlbum(
                        assetIdentifiers: assetIdentifiersToDelete
                    )

                await MainActor.run {
                    PhotoLoader.shared
                        .removeCache(for: photoToDelete.id.uuidString)
                    if photoToDelete.originalAssetIdentifier != nil {
                        PhotoLoader.shared
                            .removeCache(
                                for: "\(photoToDelete.id.uuidString)_original_preview"
                            )
                        PhotoLoader.shared
                            .removeCache(
                                for: "\(photoToDelete.id.uuidString)_original_full"
                            )
                    }

                    print("🗑️ PhotoDetailView.deletePhoto: 清理缓存完成")

                    modelContext.delete(photoToDelete)
                    try? modelContext.save()

                    print("🗑️ PhotoDetailView.deletePhoto: 数据库删除完成")

                    onPhotoDeleted?()

                    let oldIndex = currentIndex
                    let willBeEmpty = localPhotos.count == 1
                    let newIndex = oldIndex == localPhotos.count - 1 ? max(
                        oldIndex - 1,
                        0
                    ) : oldIndex

                    print("🗑️ PhotoDetailView.deletePhoto: 准备切换索引 - oldIndex: \(oldIndex)，newIndex: \(newIndex)，willBeEmpty: \(willBeEmpty)，剩余照片数: \(localPhotos.count - 1)")

                    if !willBeEmpty {
                        currentIndex = newIndex
                        localPhotos.remove(at: oldIndex)
                        showingOriginal = false
                        hasOriginal = false
                        print("✅ PhotoDetailView.deletePhoto: 索引切换完成，新索引: \(currentIndex)，照片数: \(localPhotos.count)")
                    } else {
                        localPhotos.remove(at: oldIndex)
                        if let onDismissOverride { onDismissOverride() } else {
                            dismiss()
                        }
                        print("📸 PhotoDetailView.deletePhoto: 照片已全部删除，关闭预览")
                    }
                }

                if !localPhotos.isEmpty {
                    scheduleStatusRefresh(for: currentIndex)
                }
            } catch {
                print("❌ PhotoDetailView.deletePhoto失败: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleStatusRefresh(for index: Int) {
        statusRefreshTask?.cancel()
        statusRefreshTask = Task {
            await refreshCurrentStatus(for: index)
        }
    }

    private func refreshCurrentStatus(for index: Int) async {
        guard localPhotos.indices.contains(index) else {
            await MainActor.run {
                hasOriginal = false
                showingOriginal = false
                isCurrentVideo = false
                isCurrentLivePhoto = false
            }
            return
        }

        let currentPhoto = localPhotos[index]

        // Update the UI immediately with persisted data to avoid flicker.
        await MainActor.run {
            isCurrentVideo = currentPhoto.mediaType == 2
            isCurrentLivePhoto = currentPhoto.isLivePhoto
        }

        let shouldUseOriginal = await MainActor.run { showingOriginal }
        let targetAssetId = shouldUseOriginal
            ? (currentPhoto.originalAssetIdentifier ?? currentPhoto.assetIdentifier)
            : currentPhoto.assetIdentifier

        // Check original image availability and preload in the background.
        let originalExists = await Task.detached(priority: .userInitiated) {
            guard let originalId = currentPhoto.originalAssetIdentifier, !originalId.isEmpty else {
                return false
            }
            return PHAsset.fetchAssets(withLocalIdentifiers: [originalId], options: nil).firstObject != nil
        }.value

        await MainActor.run {
            hasOriginal = originalExists
            if !originalExists {
                showingOriginal = false
            }
        }

        if originalExists {
            originalPrefetchTask?.cancel()
            originalPrefetchTask = Task {
                _ = await currentPhoto.loadOriginalImage(
                    targetSize: PhotoLoader.detailMaxSize,
                    cacheKeySuffix: "original_preview"
                )
            }
        }
    }
}

// MARK: - ActivityViewController Wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _: UIActivityViewController,
        context _: Context
    ) {
        // No updates needed
    }
}

final class ShareablePhotoItem: NSObject, Identifiable, UIActivityItemSource {
    let id = UUID()
    private let image: UIImage
    private let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_: UIActivityViewController, itemForActivityType _: UIActivity.ActivityType?) -> Any {
        image
    }

    func activityViewController(_: UIActivityViewController, subjectForActivityType _: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewController(_: UIActivityViewController, thumbnailImageForActivityType _: UIActivity.ActivityType?, suggestedSize _: CGSize) -> UIImage? {
        image
    }

    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

struct PhotoDetailPreview: View {
    var body: some View {
        let samplePhotos = (1 ... 5).map {
            let photo = PhotoAsset(
                previewAssetIdentifier: "preview_asset_\($0)",
                title: "Sample Photo \($0)"
            )
            // Add aesthetic ratings to photos in preview            photo.aestheticsScore = Float.random(in: 6.0 ... 9.5)
            // Add original image identifiers to some photos to test comparison.
            if $0 % 2 == 0 {
                photo.originalAssetIdentifier = "preview_original_\($0)"
            }
            // Add simulated EXIF metadata.
            let metadataDict: [String: Any] = [
                "{Exif}": [
                    "FNumber": 2.8,
                    "ExposureTime": 0.008,
                    "ISOSpeedRatings": [400],
                    "FocalLength": 28.0,
                ],
                "{TIFF}": [
                    "Make": "Apple",
                    "Model": "iPhone 16 Pro",
                ],
                "PixelWidth": 4032,
                "PixelHeight": 3024,
            ]
            photo.metadata = DictionarySerializer
                .encodeDictionaryToData(metadataDict)
            return photo
        }

        let permissionManager = PermissionManager.shared
        permissionManager.photoLibraryStatus = .authorized

        return PhotoDetailView(
            photos: samplePhotos,
            currentIndex: 0,
            onPhotoDeleted: nil,
            onBackToCamera: nil
        )
        .modelContainer(for: PhotoAsset.self, inMemory: true)
        .environmentObject(permissionManager)
    }
}

#Preview {
    PhotoDetailPreview()
}
