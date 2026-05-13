import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var cube: UTType { UTType(filenameExtension: "cube") ?? .data }
}

/// Filter selection view component
struct FilterGalleryView: View {
    static let favoriteAnchorName = String.filterGalleryFavorites.localized
    static let filmSimulationAnchorName = String.filterGalleryFilmSimulation.localized
    static let customAnchorName = String.commonCustom.localized

    @ObservedObject var filterManager: FilterManager = .shared
    @ObservedObject private var tutorialManager = TutorialManager.shared
    @Binding var isPresented: Bool
    var latestPhoto: PhotoAsset?
    var viewState: CameraViewState?
    var settingsState: CameraSettingsState?
    var onShutterAction: (() -> Void)?

    @AppStorage("selectedFilmEffect") private var selectedFilmEffectRaw: String = FilmEffectType.allCases.first?.rawValue ?? ""

    @State private var anchorTarget: String?
    @State private var showFilterSettings = false
    @State private var showFileImporter = false
    @State private var showRemoteImportAlert = false
    @State private var remoteImportURL = ""
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    @State private var isEffectMode = false
    @State private var isPresetEditorMode = false
    @State private var selectedEffect: FilmEffectType = .allCases.first ?? .vignette

    @State private var showTutorial = false

    private var allAnchors: [String] {
        [Self.favoriteAnchorName, Self.filmSimulationAnchorName, Self.customAnchorName]
    }

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var galleryHeight: CGFloat {
        if isPresetEditorMode { return 300 }
        return isSmallScreen ? 76 : 88
    }

    private var currentPresetIndex: Int? {
        guard let presetID = filterManager.selectedFilter.info?.filmEffects.filmPresetID else {
            return nil
        }
        return FilmPreset.all.firstIndex(where: { $0.id == presetID })
    }

    var body: some View {
        Group {
            if isPresetEditorMode, let index = currentPresetIndex {
                FilmPresetEditorView(presetIndex: index) {
                    withAnimation {
                        isPresetEditorMode = false
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    // tab bar
                    FilterAnchorBar(
                        allAnchors: allAnchors,
                        showFilterSettings: $showFilterSettings,
                        isEffectMode: $isEffectMode,
                        isPresetEditorMode: $isPresetEditorMode,
                        onAnchorTap: {
                            withAnimation {
                                isEffectMode = false
                                isPresetEditorMode = false
                            }
                            anchorTarget = $0
                        }
                    )

                    ZStack(alignment: .leading) {
                        if isEffectMode {
                            FilmEffectSettingsView(filterManager: filterManager, selectedEffect: $selectedEffect)
                                .transition(.opacity)
                        } else {
                            // Bottom layer: filter scroll area (full screen width)
                            FilterScrollGroups(
                                filterManager: filterManager,
                                anchorTarget: $anchorTarget,
                                layoutFavorites: filterManager.visibleFavoriteFilters,
                                onFavoriteToggle: toggleFavorite,
                                onCustomFavoriteToggle: toggleCustomFavorite,
                                showFileImporter: $showFileImporter,
                                showRemoteImportAlert: $showRemoteImportAlert,
                                remoteImportURL: $remoteImportURL
                            )
                            .transition(.opacity)
                        }

                        // Top level: floating vertical slider
                        if !(filterManager.selectedFilter.isFilmSimulationOrNone && !isEffectMode) {
                            FilterIntensityVerticalSlider(
                                currentIntensity: Binding(
                                    get: {
                                        if isEffectMode {
                                            switch selectedEffect {
                                            case .cineTone: return Float(filterManager.cineToneIntensity)
                                            case .halation: return Float(filterManager.halationIntensity)
                                            case .bloom: return Float(filterManager.bloomIntensity)
                                            case .grain: return Float(filterManager.grainIntensity)
                                            case .fog: return Float(filterManager.fogIntensity)
                                            case .vignette: return Float(filterManager.vignetteIntensity)
                                            case .lightLeak: return Float(filterManager.lightLeakIntensity)
                                            }
                                        } else {
                                            return filterManager.getIntensity(for: filterManager.selectedFilter)
                                        }
                                    },
                                    set: { _ in } // Ignored when onIntensityChange is provided
                                ),
                                minValue: isEffectMode ? 0.0 : FilterIntensityConstants.minIntensity,
                                iconName: isEffectMode ? selectedEffect.icon : "camera.filters",
                                onIntensityChange: isEffectMode ? { val in
                                    switch selectedEffect {
                                    case .cineTone: filterManager.cineToneIntensity = Double(val)
                                    case .halation: filterManager.halationIntensity = Double(val)
                                    case .bloom: filterManager.bloomIntensity = Double(val)
                                    case .grain: filterManager.grainIntensity = Double(val)
                                    case .fog: filterManager.fogIntensity = Double(val)
                                    case .vignette: filterManager.vignetteIntensity = Double(val)
                                    case .lightLeak: filterManager.lightLeakIntensity = Double(val)
                                    }
                                } : nil
                            )
                            .padding(.leading, 12)
                        }
                    }
                    .frame(height: galleryHeight)

                    // Bottom operation button
                    ActionButtons(
                        filterManager: filterManager,
                        isPresented: $isPresented,
                        latestPhoto: latestPhoto,
                        viewState: viewState,
                        settingsState: settingsState,
                        onShutterAction: onShutterAction
                    )
                }
            }
        }
        .background(importAlerts)
        .fullScreenCover(isPresented: $showFilterSettings) {
            FilterSettingsView(
                isPresented: $showFilterSettings
            )
            .buttonStyle(.plain)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.cube],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                if let newFilter = CustomFilterManager.shared.importFilter(from: url) {
                    DispatchQueue.main.async {
                        filterManager.selectCustomFilter(newFilter)
                    }
                }
            case let .failure(error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .onAppear {
            // Show guidance when filter library is first displayed
            if !tutorialManager.hasShownFilterGalleryTutorial {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showTutorial = true
                }
            }
        }
        .overlay {
            if showTutorial {
                FilterGalleryTutorialView(isPresented: $showTutorial)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showTutorial)
        .onAppear {
            let cachedEffect = FilmEffectType(rawValue: selectedFilmEffectRaw) ?? FilmEffectType.allCases.first ?? .vignette
            selectedEffect = cachedEffect
        }
        .onChange(of: selectedEffect) { _, newValue in
            selectedFilmEffectRaw = newValue.rawValue
        }
    }

    private func handleRemoteImport() {
        guard !remoteImportURL.isEmpty else { return }

        CustomFilterManager.shared.importFilter(fromRemote: remoteImportURL) { result in
            DispatchQueue.main.async {
                switch result {
                case let .success(newFilter):
                    filterManager.selectCustomFilter(newFilter)
                case let .failure(error):
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            }
        }
    }

    private var importAlerts: some View {
        EmptyView()
            .alert(String.filterImportFromUrlTitle.localized, isPresented: $showRemoteImportAlert) {
                TextField(String.filterImportUrlPlaceholder.localized, text: $remoteImportURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(String.commonCancel.localized, role: .cancel) {}
                Button(String.filterGalleryImport.localized) {
                    handleRemoteImport()
                }
            } message: {
                Text(String.filterImportUrlMessage.localized)
            }
            .alert(String.filterImportFailedTitle.localized, isPresented: $showImportError) {
                Button(String.filterImportConfirm.localized, role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
    }

    private func toggleFavorite(_ filter: FilterIdentifier) {
        let wasNotFavorite = !filterManager.isFavorite(filter)
        filterManager.toggleFavorite(filter)
        if wasNotFavorite {
            withAnimation(.easeInOut(duration: 0.3)) { anchorTarget = filter.id }
        }
    }

    private func toggleCustomFavorite(_ filter: CustomFilter) {
        let wasNotFavorite = !filter.isFavorite
        CustomFilterManager.shared.toggleFavorite(filter)
        if wasNotFavorite {
            withAnimation(.easeInOut(duration: 0.3)) { anchorTarget = "custom:\(filter.id.uuidString)" }
        }
    }
}

// MARK: - Separate action button component

private struct FilterRotatableView<Content: View>: View {
    @ObservedObject var viewState: CameraViewState
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .rotationEffect(.degrees(viewState.rotation))
            .animation(.easeInOut(duration: 0.3), value: viewState.rotation)
    }
}

struct ActionButtons: View, Equatable {
    @ObservedObject var filterManager: FilterManager
    @Binding var isPresented: Bool
    var latestPhoto: PhotoAsset?

    var viewState: CameraViewState?
    var settingsState: CameraSettingsState?
    var onShutterAction: (() -> Void)?

    private let sideButtonSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 12) {
            if let viewState, let settingsState {
                FilterRotatableView(viewState: viewState) {
                    PhotoGalleryButton(
                        latestPhoto: latestPhoto,
                        rotation: 0,
                        isCircular: true,
                        onTap: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            viewState.showingPhotoGallery = true
                        }
                    )
                }
                .scaleEffect(sideButtonSize / (UIScreen.main.bounds.width < 390 ? 40 : 48))
                .frame(width: sideButtonSize, height: sideButtonSize)
            } else {
                Spacer()
                    .frame(width: sideButtonSize)
            }

            Spacer()

            if let settingsState {
                CaptureButton(
                    settingsState: settingsState,
                    action: onShutterAction
                )
                .scaleEffect(0.65)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: sideButtonSize, height: sideButtonSize)
                    .background(GlassButtonBackground(isCircle: true))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
    }

    static func == (lhs: ActionButtons, rhs: ActionButtons) -> Bool {
        lhs.filterManager.selectedFilter == rhs.filterManager.selectedFilter &&
            lhs.filterManager.selectedCustomFilter?.id == rhs.filterManager.selectedCustomFilter?.id &&
            lhs.isPresented == rhs.isPresented &&
            lhs.latestPhoto?.id == rhs.latestPhoto?.id &&
            lhs.settingsState?.previewLatestPhoto == rhs.settingsState?.previewLatestPhoto
    }
}

struct FilterAnchorBar: View {
    let allAnchors: [String]
    @Binding var showFilterSettings: Bool
    @Binding var isEffectMode: Bool
    @Binding var isPresetEditorMode: Bool
    let onAnchorTap: (String) -> Void

    private static let anchorIcons: [String: String] = [
        FilterGalleryView.favoriteAnchorName: "heart",
        FilterGalleryView.filmSimulationAnchorName: "film",
        FilterGalleryView.customAnchorName: "cube",
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { showFilterSettings = true } label: {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(GlassButtonBackground(cornerRadius: 10))
            }
            .padding(.leading, 12)

            HStack(spacing: 0) {
                ForEach(allAnchors, id: \.self) { anchor in
                    Button { onAnchorTap(anchor) } label: {
                        HStack(spacing: 4) {
                            if let icon = Self.anchorIcons[anchor] {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(anchor)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor((isEffectMode || isPresetEditorMode) ? .white.opacity(0.5) : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                }
            }

            Spacer()

            #if DEBUG
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresetEditorMode.toggle()
                        if isPresetEditorMode { isEffectMode = false }
                    }
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isPresetEditorMode ? .yellow : .white)
                        .frame(width: 30, height: 30)
                        .background(GlassButtonBackground(cornerRadius: 10))
                }
                .padding(.trailing, 8)
            #endif

            // Effects Toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isEffectMode.toggle()
                    if isEffectMode { isPresetEditorMode = false }
                }
            } label: {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isEffectMode ? .accentColor : .white)
                    .frame(width: 30, height: 30)
                    .background(GlassButtonBackground(cornerRadius: 10))
            }
            .padding(.trailing, 12)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Universal glass button background

private struct GlassButtonBackground: View {
    var cornerRadius: CGFloat = 10
    var isCircle: Bool = false

    var body: some View {
        Group {
            if isCircle {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Filter Set

struct FilterScrollGroups: View {
    @ObservedObject var filterManager: FilterManager
    @ObservedObject var customFilterManager: CustomFilterManager = .shared
    @Binding var anchorTarget: String?
    var layoutFavorites: [FilterIdentifier]
    var onFavoriteToggle: (FilterIdentifier) -> Void
    var onCustomFavoriteToggle: (CustomFilter) -> Void
    @Binding var showFileImporter: Bool
    @Binding var showRemoteImportAlert: Bool
    @Binding var remoteImportURL: String

    var body: some View {
        if #available(iOS 17.5, *) {
            FilterScrollGroupsModern(
                filterManager: filterManager,
                customFilterManager: customFilterManager,
                anchorTarget: $anchorTarget,
                layoutFavorites: layoutFavorites,
                onFavoriteToggle: onFavoriteToggle,
                onCustomFavoriteToggle: onCustomFavoriteToggle,
                showFileImporter: $showFileImporter,
                showRemoteImportAlert: $showRemoteImportAlert,
                remoteImportURL: $remoteImportURL
            )
        } else {
            FilterScrollGroupsLegacy(
                filterManager: filterManager,
                customFilterManager: customFilterManager,
                anchorTarget: $anchorTarget,
                layoutFavorites: layoutFavorites,
                onFavoriteToggle: onFavoriteToggle,
                onCustomFavoriteToggle: onCustomFavoriteToggle,
                showFileImporter: $showFileImporter,
                showRemoteImportAlert: $showRemoteImportAlert,
                remoteImportURL: $remoteImportURL
            )
        }
    }
}

struct FilterScrollGroupsModern: View {
    @ObservedObject var filterManager: FilterManager
    @ObservedObject var customFilterManager: CustomFilterManager
    @Binding var anchorTarget: String?
    var layoutFavorites: [FilterIdentifier]
    var onFavoriteToggle: (FilterIdentifier) -> Void
    var onCustomFavoriteToggle: (CustomFilter) -> Void
    @Binding var showFileImporter: Bool
    @Binding var showRemoteImportAlert: Bool
    @Binding var remoteImportURL: String

    @State private var scrolledID: String? = nil
    @State private var isDeleteMode = false

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var itemWidth: CGFloat {
        isSmallScreen ? 76 : 88
    }

    private var scrollViewHeight: CGFloat {
        isSmallScreen ? 76 : 88
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        filterGroupsContent(geometry: geometry)
                    }
                    .padding(.vertical, 6)
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrolledID)
                .scrollTargetBehavior(.viewAligned)
                .safeAreaPadding(.horizontal, (geometry.size.width - itemWidth) / 2)
                .onAppear {
                    syncScrolledID()
                }
                .onChange(of: filterManager.selectedFilter) { _, _ in
                    syncScrolledID()
                }
                .onChange(of: filterManager.selectedCustomFilter?.id) { _, _ in
                    syncScrolledID()
                }
                .onChange(of: scrolledID) { _, newValue in
                    handleScrollChange(to: newValue)
                }
                .onChange(of: anchorTarget) { _, newTarget in
                    if let target = newTarget {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        DispatchQueue.main.async {
                            anchorTarget = nil
                        }
                    }
                }
            }
        }
        .frame(height: scrollViewHeight)
    }

    private func syncScrolledID() {
        let currentID: String
        if filterManager.selectedFilter.category == .custom,
           let customId = filterManager.selectedCustomFilter?.id.uuidString
        {
            currentID = "custom:\(customId)"
        } else {
            currentID = filterManager.selectedFilter.id
        }

        if scrolledID != currentID {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrolledID = currentID
            }
        }
    }

    private func handleScrollChange(to newValue: String?) {
        guard let idString = newValue else { return }

        // parse identifier
        if idString.hasPrefix("custom:"), let uuidString = idString.split(separator: ":").last {
            if let uuid = UUID(uuidString: String(uuidString)),
               let customFilter = customFilterManager.customFilters.first(where: { $0.id == uuid })
            {
                if filterManager.selectedFilter.category != .custom || filterManager.selectedCustomFilter?.id != uuid {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    filterManager.selectCustomFilter(customFilter)
                }
            }
        } else if let identifier = parseFilterIdentifier(from: idString) {
            if filterManager.selectedFilter != identifier {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                filterManager.selectedFilter = identifier
            }
        }
    }

    private func parseFilterIdentifier(from idString: String) -> FilterIdentifier? {
        let parts = idString.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let category = FilterCategory(rawValue: String(parts[0]))
        else {
            return nil
        }
        return FilterIdentifier(category: category, name: String(parts[1]))
    }

    @ViewBuilder
    private func filterGroupsContent(geometry: GeometryProxy) -> some View {
        let visibleFavorites = layoutFavorites.filter {
            !$0.isFilmSimulationOrNone
        }

        let favoritedCustomFilters = customFilterManager.customFilters.filter(\.isFavorite)

        let favoriteSet = Set(visibleFavorites)
        let allNonFavoriteFilters = filterManager.allVisibleFilters.filter {
            !favoriteSet.contains($0) && !$0.isFilmSimulationOrNone
        }

        let filmSimulationFilters = FilterIdentifier.filmSimulationFilters.filter { filterManager.isFilterVisible($0) }

        FavoritesFilterGroup(
            id: FilterGalleryView.favoriteAnchorName,
            filters: visibleFavorites,
            customFilters: favoritedCustomFilters,
            filterManager: filterManager,
            onFavoriteToggle: onFavoriteToggle,
            onCustomFavoriteToggle: onCustomFavoriteToggle,
            isDeleteMode: isDeleteMode
        )

        if !filmSimulationFilters.isEmpty {
            FilterGroup(id: String.filterGalleryFilmSimulation.localized, filters: filmSimulationFilters, filterManager: filterManager, onFavoriteToggle: onFavoriteToggle)
        }

        if !allNonFavoriteFilters.isEmpty {
            FilterGroup(id: "allNonFavoriteFilters", filters: allNonFavoriteFilters, filterManager: filterManager, onFavoriteToggle: onFavoriteToggle)
        }

        // Custom filter grouping
        CustomFilterGroup(
            id: FilterGalleryView.customAnchorName,
            filterManager: filterManager,
            onCustomFavoriteToggle: onCustomFavoriteToggle,
            showFileImporter: $showFileImporter,
            showRemoteImportAlert: $showRemoteImportAlert,
            remoteImportURL: $remoteImportURL,
            geometry: geometry,
            isDeleteMode: $isDeleteMode
        )
    }
}

// MARK: - filter group (subcomponent)

struct FavoritesFilterGroup: View {
    let id: String
    let filters: [FilterIdentifier]
    let customFilters: [CustomFilter]
    @ObservedObject var filterManager: FilterManager
    var onFavoriteToggle: (FilterIdentifier) -> Void
    var onCustomFavoriteToggle: (CustomFilter) -> Void
    var isDeleteMode: Bool

    private var hasContent: Bool { !filters.isEmpty || !customFilters.isEmpty }

    var body: some View {
        Group {
            if hasContent {
                ForEach(filters, id: \.id) { filter in
                    FilterCardWithFavorite(filterManager: filterManager, filter: filter, onFavoriteToggle: onFavoriteToggle)
                        .id(filter.id)
                }
                ForEach(customFilters) { filter in
                    CustomFilterCard(filter: filter, filterManager: filterManager, isDeleteMode: isDeleteMode, onFavoriteToggle: onCustomFavoriteToggle)
                        .id("custom:\(filter.id.uuidString)")
                }
                DividerLine()
            } else {
                EmptyFavoritePlaceholder()
            }
        }
        .id(id)
    }
}

struct FilterGroup: View {
    let id: String
    let filters: [FilterIdentifier]
    @ObservedObject var filterManager: FilterManager
    var onFavoriteToggle: (FilterIdentifier) -> Void

    var body: some View {
        Group {
            ForEach(filters, id: \.id) { filter in
                FilterCardWithFavorite(filterManager: filterManager, filter: filter, onFavoriteToggle: onFavoriteToggle)
                    .id(filter.id)
            }
            if !filters.isEmpty { DividerLine() }
        }
        .id(id)
    }
}

// MARK: - dividing line component

struct DividerLine: View {
    var body: some View {
        VStack {
            Spacer()
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05),
                            Color.clear,
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.2)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 0.5)
                        .offset(x: 0.6)
                )
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Empty collection placeholder component

struct EmptyFavoritePlaceholder: View {
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var width: CGFloat { isSmallScreen ? 72 : 88 }
    private var height: CGFloat { isSmallScreen ? 54 : 66 }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.slash")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .white.opacity(0.1), radius: 0, x: 0, y: 1)
                .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: -0.5)

            Text(String.noFavoriteFilters.localized)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .shadow(color: .white.opacity(0.1), radius: 0, x: 0, y: 1)
                .shadow(color: .black.opacity(0.2), radius: 0, x: 0, y: -0.5)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.vertical, 3)
    }
}

struct FilterCardWithFavorite: View, Equatable {
    @ObservedObject var filterManager: FilterManager
    let filter: FilterIdentifier
    var onFavoriteToggle: ((FilterIdentifier) -> Void)?

    private var isFavorite: Bool { filterManager.isFavorite(filter) }
    private var isSelected: Bool { filterManager.selectedFilter == filter }
    private var isFilmSimulationOrNone: Bool { filter.isFilmSimulationOrNone }
    private var isFilmSimulation: Bool { filter.isFilmSimulation }

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var cardWidth: CGFloat { isSmallScreen ? 72 : 88 }
    private var cardHeight: CGFloat { isSmallScreen ? 54 : 66 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            filterCardView
            if isFavorite, !isFilmSimulationOrNone {
                FavoriteIcon(isFavorite: true)
            }
        }
        .padding(.vertical, 3)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            filterManager.selectedFilter = filter
        }
        .if(!isFilmSimulationOrNone) { view in
            view.onLongPressGesture {
                (isFavorite ? UIImpactFeedbackGenerator(style: .light) : nil)?.impactOccurred()
                if !isFavorite { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                onFavoriteToggle?(filter)
            }
        }
    }

    @ViewBuilder
    private var filterCardView: some View {
        if let displayConfig = filterManager.getDisplayConfig(for: filter) {
            FilterCard(displayConfig: displayConfig)
                .scaleEffect(cardWidth / 300)
                .frame(width: cardWidth, height: cardHeight)
                // Applies rectangular cropping only to non-Film simulation filters, Film simulation filters maintain original image outlines
                .if(!isFilmSimulation) { view in
                    view.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .overlay(SelectionBorder(isSelected: isSelected && !isFilmSimulation))
                // Normal filters apply shadows, Film simulation filters use base effects
                .shadow(
                    color: .black.opacity(isSelected ? 0.3 : 0.1),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: isSelected ? 2 : 1
                )
                .background {
                    if isFilmSimulation, isSelected {
                        ZStack {
                            // Bottom projection
                            Ellipse()
                                .fill(.black.opacity(0.2))
                                .frame(width: cardWidth * 0.6, height: 4)
                                .blur(radius: 2)
                                .offset(y: cardHeight / 2 + 5)

                            // Simple base
                            Capsule()
                                .fill(.white.opacity(0.5))
                                .frame(width: cardWidth * 0.4, height: 3)
                                .offset(y: cardHeight / 2 + 4)
                        }
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .frame(width: cardWidth, height: cardHeight)
                .overlay(SelectionBorder(isSelected: isSelected && !isFilmSimulation))
                .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? 4 : 2, x: 0, y: isSelected ? 2 : 1)
        }
    }

    static func == (lhs: FilterCardWithFavorite, rhs: FilterCardWithFavorite) -> Bool {
        lhs.filter == rhs.filter &&
            lhs.filterManager.isFavorite(lhs.filter) == rhs.filterManager.isFavorite(rhs.filter) &&
            (lhs.filterManager.selectedFilter == lhs.filter) == (rhs.filterManager.selectedFilter == rhs.filter)
    }
}

// MARK: - View condition modifier extension

private extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Select the border

private struct SelectionBorder: View {
    let isSelected: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                isSelected ? Color.white : Color.clear,
                lineWidth: 2
            )
            .shadow(color: isSelected ? Color.black.opacity(0.2) : .clear, radius: 2)
    }
}

// MARK: - Non-interactive collection icon component

private struct FavoriteIcon: View {
    let isFavorite: Bool

    var body: some View {
        Image(systemName: isFavorite ? "heart.fill" : "heart")
            .foregroundColor(isFavorite ? .red : .white)
            .font(.system(size: 12))
            .padding(6)
    }
}

// MARK: - Custom filter related components

struct CustomFilterGroup: View {
    let id: String
    @ObservedObject var customFilterManager = CustomFilterManager.shared
    @ObservedObject var filterManager: FilterManager
    var onCustomFavoriteToggle: (CustomFilter) -> Void
    @Binding var showFileImporter: Bool
    @Binding var showRemoteImportAlert: Bool
    @Binding var remoteImportURL: String
    let geometry: GeometryProxy
    @Binding var isDeleteMode: Bool

    var body: some View {
        Group {
            ForEach(customFilterManager.customFilters.filter { !$0.isFavorite }) { filter in
                CustomFilterCard(
                    filter: filter,
                    filterManager: filterManager,
                    isDeleteMode: isDeleteMode,
                    onFavoriteToggle: onCustomFavoriteToggle
                )
                .id("custom:\(filter.id.uuidString)")
            }

            ImportFilterCard(
                showFileImporter: $showFileImporter,
                showRemoteImportAlert: $showRemoteImportAlert,
                remoteImportURL: $remoteImportURL
            )

            if !customFilterManager.customFilters.isEmpty {
                DeleteModeToggleCard(isDeleteMode: $isDeleteMode)
            }
        }
        .id(id)
    }
}

struct ImportFilterCard: View {
    @Binding var showFileImporter: Bool
    @Binding var showRemoteImportAlert: Bool
    @Binding var remoteImportURL: String

    var body: some View {
        Menu {
            Button { showFileImporter = true } label: {
                Label(String.filterImportFromFile.localized, systemImage: "doc")
            }
            Button {
                remoteImportURL = ""
                showRemoteImportAlert = true
            } label: {
                Label(String.filterImportFromUrl.localized, systemImage: "link")
            }
        } label: {
            GlassActionCard(icon: "plus", title: String.filterGalleryImport.localized)
        }
    }
}

struct DeleteModeToggleCard: View {
    @Binding var isDeleteMode: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isDeleteMode.toggle() }
        } label: {
            GlassActionCard(
                icon: isDeleteMode ? "checkmark" : "trash",
                title: isDeleteMode ? String.commonDone.localized : String.commonDelete.localized,
                isActive: isDeleteMode
            )
        }
    }
}

// MARK: - Universal Glass Operation Card

private struct GlassActionCard: View {
    let icon: String
    let title: String
    var isActive: Bool = false

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var cardSize: CGFloat { isSmallScreen ? 54 : 66 }

    private var foregroundColor: Color { isActive ? .accentColor : .white.opacity(0.9) }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(foregroundColor)
        .frame(width: cardSize, height: cardSize)
        .background(GlassButtonBackground(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.2)
        )
        .padding(.vertical, 2)
    }
}

struct CustomFilterCard: View {
    let filter: CustomFilter
    @ObservedObject var filterManager: FilterManager
    var isDeleteMode: Bool
    var onFavoriteToggle: ((CustomFilter) -> Void)?

    private var isSelected: Bool {
        filterManager.selectedFilter.category == .custom && filterManager.selectedCustomFilter?.id == filter.id
    }

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var cardWidth: CGFloat { isSmallScreen ? 72 : 88 }
    private var cardHeight: CGFloat { isSmallScreen ? 54 : 66 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .frame(width: cardWidth, height: cardHeight)
                .overlay(
                    Text(filter.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                )
                .overlay(SelectionBorder(isSelected: isSelected))
                .shadow(color: .black.opacity(isSelected ? 0.3 : 0.1), radius: isSelected ? 4 : 2, x: 0, y: isSelected ? 2 : 1)

            if filter.isFavorite { FavoriteIcon(isFavorite: true) }

            if isDeleteMode {
                Button {
                    CustomFilterManager.shared.deleteFilter(filter)
                    if isSelected {
                        filterManager.selectedFilter = .fChrome
                        filterManager.selectedCustomFilter = nil
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.system(size: 22))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .offset(x: 6, y: -6)
            }
        }
        .padding(.vertical, 3)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            filterManager.selectCustomFilter(filter)
        }
        .onLongPressGesture {
            (filter.isFavorite ? UIImpactFeedbackGenerator(style: .light) : nil)?.impactOccurred()
            if !filter.isFavorite { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            onFavoriteToggle?(filter)
        }
    }
}

#Preview {
    FilterGalleryView(
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
