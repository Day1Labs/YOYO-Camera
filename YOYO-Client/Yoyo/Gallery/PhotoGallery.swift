import Photos
import SwiftData
import SwiftUI

// MARK: - Main View

struct PhotoFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct PhotoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var permissionManager: PermissionManager
    @ObservedObject private var authManager = AuthManager.shared

    let autoPreviewLatest: Bool
    @StateObject private var viewModel: PhotoGalleryViewModel

    @State private var selectedPhotoId: PhotoAsset.ID? = nil
    @State private var suppressInitialContent: Bool = false
    private let initialPhotoId: PhotoAsset.ID? // Store the initial photo to select after loading

    // Swipe Selection State
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var dragStartID: UUID? = nil
    @State private var initialSelectedPhotos: Set<UUID> = []
    @State private var isSelectingMore = true
    @State private var currentDragLocation: CGPoint? = nil

    private enum DragState {
        case inactive
        case selecting
        case scrolling
    }

    @State private var dragState: DragState = .inactive

    /// Calculate the index of the currently selected photo for `PhotoDetailView`.
    private var selectedPhotoIndex: Int? {
        guard let id = selectedPhotoId else { return nil }
        return viewModel.photos.firstIndex(where: { $0.id == id })
    }

    init(autoPreviewLatest: Bool = false, initialPhotos: [PhotoAsset] = []) {
        self.autoPreviewLatest = autoPreviewLatest
        initialPhotoId = initialPhotos.first?.id

        // Don't set selectedPhotoId in init; wait until loadPhotos completes
        // so that PhotoDetailView receives the full photo list for swiping
        let shouldAutoPreview = autoPreviewLatest && !initialPhotos.isEmpty
        _selectedPhotoId = State(initialValue: nil)
        _suppressInitialContent = State(initialValue: shouldAutoPreview)

        _viewModel = StateObject(wrappedValue: PhotoGalleryViewModel(initialPhotos: initialPhotos))
    }

    var body: some View {
        ZStack {
            Color(.black)
                .ignoresSafeArea()

            if !suppressInitialContent {
                VStack(spacing: 0) {
                    if viewModel.photos.isEmpty {
                        statusView
                    } else {
                        headerView
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        photoGridView
                    }
                }
            }
        }
        .coordinateSpace(name: "gallery")
        .overlay(bottomBar, alignment: .bottom)
        .overlay(detailOverlay)
        .onPreferenceChange(PhotoFramePreferenceKey.self) { preferences in
            itemFrames = preferences
            // When scrolling changes item frames, retrigger selection while dragging.
            if let location = currentDragLocation, let startID = dragStartID {
                if let currentID = preferences.first(where: { $0.value.contains(location) })?.key {
                    updateSelection(from: startID, to: currentID)
                }
            }
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .trackScreen(name: "PhotoGallery")
        .task {
            viewModel.setup(modelContext: modelContext, permissionManager: permissionManager)
            await viewModel.loadPhotos(skipValidation: false)

            // After loading and validation, if autoPreviewLatest is true, show the first photo
            if autoPreviewLatest, !viewModel.photos.isEmpty {
                await MainActor.run {
                    // Try to select the initial photo if it exists in the loaded list
                    if let initialPhotoId,
                       viewModel.photos.contains(where: { $0.id == initialPhotoId })
                    {
                        selectedPhotoId = initialPhotoId
                    } else {
                        selectedPhotoId = viewModel.photos.first?.id
                    }
                    suppressInitialContent = true
                }
            }
        }
        .onChange(of: selectedPhotoId) { _, new in
            if new == nil {
                suppressInitialContent = false
                Task { await viewModel.loadPhotos(skipValidation: false) }
            }
        }
        .fullScreenCover(isPresented: $authManager.showAuthSheet) {
            UnifiedAuthSheet()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    private var statusView: some View {
        if viewModel.isLoading {
            loadingStateView
        } else if let error = viewModel.loadingError {
            errorStateView(error)
        } else {
            emptyStateView
        }
    }

    private var headerView: some View {
        ZStack {
            Text(
                viewModel.isSelecting ? String.selectedCount
                    .localized(viewModel.selectedPhotos.count) : String.photosTitle.localized
            )
            .font(.headline)
            .foregroundColor(.white.opacity(0.9))

            HStack {
                if viewModel.isSelecting {
                    Button(
                        viewModel.selectedPhotos.count == viewModel.photos.count ? String.deselectAll.localized : String.selectAll.localized
                    ) {
                        if viewModel.selectedPhotos.count == viewModel.photos.count {
                            viewModel.selectedPhotos.removeAll()
                        } else {
                            viewModel.selectedPhotos = Set(viewModel.photos.map(\.id))
                        }
                    }
                    .buttonStyle(GalleryButtonStyle())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                Button(viewModel.isSelecting ? String.commonCancel.localized : String.commonSelect.localized) {
                    viewModel.toggleSelectionMode()
                }
                .buttonStyle(GalleryButtonStyle())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var photoGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1),
                ],
                spacing: 1
            ) {
                ForEach(viewModel.photos) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        isSelected: viewModel.selectedPhotos.contains(photo.id)
                    )
                    .background(
                        GeometryReader { itemGeo in
                            Color.clear
                                .preference(key: PhotoFramePreferenceKey.self, value: [photo.id: itemGeo.frame(in: .named("gallery"))])
                        }
                    )
                    .onTapGesture {
                        if viewModel.isSelecting {
                            viewModel.toggleSelection(for: photo.id)
                        } else {
                            selectedPhotoId = photo.id
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.bottom, 100)
        }
        .scrollDisabled(dragState == .selecting)
        .simultaneousGesture(viewModel.isSelecting ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("gallery"))
            .onChanged { value in
                guard viewModel.isSelecting else { return }

                switch dragState {
                case .inactive:
                    let translation = value.translation
                    // Treat strong vertical movement as scrolling instead of selection.
                    if abs(translation.height) > abs(translation.width) * 2.5 {
                        dragState = .scrolling
                    } else {
                        dragState = .selecting
                        handleDragSelection(value)
                    }
                case .selecting:
                    handleDragSelection(value)
                case .scrolling:
                    break
                }
            }
            .onEnded { _ in
                dragStartID = nil
                currentDragLocation = nil
                dragState = .inactive
            }
    }

    private func handleDragSelection(_ value: DragGesture.Value) {
        currentDragLocation = value.location

        if dragStartID == nil {
            if let id = findID(at: value.startLocation) {
                dragStartID = id
                initialSelectedPhotos = viewModel.selectedPhotos
                isSelectingMore = !initialSelectedPhotos.contains(id)
            }
        }

        if let startID = dragStartID, let currentID = findID(at: value.location) {
            updateSelection(from: startID, to: currentID)
        }
    }

    private func findID(at location: CGPoint) -> UUID? {
        itemFrames.first { $1.contains(location) }?.key
    }

    private func updateSelection(from startID: UUID, to currentID: UUID) {
        guard let startIndex = viewModel.photos.firstIndex(where: { $0.id == startID }),
              let currentIndex = viewModel.photos.firstIndex(where: { $0.id == currentID })
        else {
            return
        }

        let rangeStart = min(startIndex, currentIndex)
        let rangeEnd = max(startIndex, currentIndex)
        let rangeIDs = Set(viewModel.photos[rangeStart ... rangeEnd].map(\.id))

        var newSelection = initialSelectedPhotos
        if isSelectingMore {
            newSelection.formUnion(rangeIDs)
        } else {
            newSelection.subtract(rangeIDs)
        }

        if newSelection != viewModel.selectedPhotos {
            viewModel.selectedPhotos = newSelection
        }
    }

    private var generateVideoButton: some View {
        let isActionable = viewModel.selectedPhotos.count >= 2 && !viewModel.isGeneratingVideo

        return Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            viewModel.generateVideoFromSelection()
        }) {
            Group {
                if viewModel.isGeneratingVideo {
                    Text("\(Int(viewModel.generationProgress * 100))%")
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Image(systemName: "movieclapper")
                        .font(.system(size: 22))
                        .foregroundColor(isActionable ? .white.opacity(0.9) : .gray)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 24, height: 24)
            .padding(20)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    }
            }
        }
        .allowsHitTesting(isActionable)
    }

    private var bottomBar: some View {
        Group {
            if !suppressInitialContent {
                VStack {
                    Spacer()
                    HStack {
                        GlassCircleButton(iconName: "camera.fill") {
                            dismiss()
                        }
                        .padding(.leading, 32)

                        Spacer()

                        if viewModel.isSelecting {
                            generateVideoButton
                                .padding(.trailing, 16)

                            GlassCircleButton(
                                iconName: "trash",
                                foregroundColor: viewModel.selectedPhotos.isEmpty ? .gray : Color(
                                    red: 255 / 255,
                                    green: 46 / 255,
                                    blue: 99 / 255
                                )
                            ) {
                                viewModel.deleteSelectedPhotos()
                            }
                            .disabled(viewModel.selectedPhotos.isEmpty)
                            .padding(.trailing, 32)
                        } else if viewModel.isGeneratingVideo {
                            generateVideoButton
                                .padding(.trailing, 32)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .frame(height: 100)
            }
        }
    }

    @ViewBuilder
    private var detailOverlay: some View {
        if let index = selectedPhotoIndex {
            ZStack {
                Color.black.ignoresSafeArea()
                PhotoDetailView(
                    photos: viewModel.photos,
                    currentIndex: index,
                    onBackToCamera: {
                        selectedPhotoId = nil
                    },
                    onDismissOverride: {
                        selectedPhotoId = nil
                    }
                )
                .environmentObject(permissionManager)
            }
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.8))
            Text(String.noPhotos.localized)
                .font(.system(size: 18))
                .foregroundColor(.gray.opacity(0.8))
            Spacer()
        }
    }

    @ViewBuilder
    private func errorStateView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.7))
            Text(error)
                .font(.caption)
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }
}

// MARK: - Button Styles

struct GalleryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundColor(.white.opacity(0.9))
            .glassCardStyle(cornerRadius: 100)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

// MARK: - Previews

#Preview {
    let container = try! ModelContainer(
        for: PhotoAsset.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    for i in 1 ... 50 {
        let photo = PhotoAsset(
            previewAssetIdentifier: "sample_asset_\(i)",
            title: "Sample Photo \(i)"
        )
        if i % 3 == 0 {
            photo.isFavorite = true
        }
        container.mainContext.insert(photo)
    }

    let permissionManager = PermissionManager.shared
    permissionManager.photoLibraryStatus = .authorized

    return PhotoGalleryView()
        .modelContainer(container)
        .environmentObject(permissionManager)
}
