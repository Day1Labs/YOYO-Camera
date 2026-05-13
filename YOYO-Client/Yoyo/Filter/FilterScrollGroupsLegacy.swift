import SwiftUI

struct FilterScrollGroupsLegacy: View {
    @ObservedObject var filterManager: FilterManager
    @ObservedObject var customFilterManager: CustomFilterManager
    @Binding var anchorTarget: String?
    var layoutFavorites: [FilterIdentifier]
    var onFavoriteToggle: (FilterIdentifier) -> Void
    var onCustomFavoriteToggle: (CustomFilter) -> Void
    @Binding var showFileImporter: Bool
    @Binding var showRemoteImportAlert: Bool
    @Binding var remoteImportURL: String

    @State private var isDeleteMode = false
    @StateObject private var page = Page.first()

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var itemWidth: CGFloat {
        isSmallScreen ? 80 : 96
    }

    private var scrollViewHeight: CGFloat {
        isSmallScreen ? 84 : 96
    }

    private enum PagerItem: Identifiable, Equatable {
        case favorite(FilterIdentifier, hasDivider: Bool)
        case customFavorite(CustomFilter, hasDivider: Bool)
        case emptyFavorite
        case filmSimulation(FilterIdentifier, hasDivider: Bool)
        case filter(FilterIdentifier, hasDivider: Bool)
        case customFilter(CustomFilter)
        case importCard
        case deleteToggle

        var id: String {
            switch self {
            case let .favorite(f, _): return "fav-\(f.id)"
            case let .customFavorite(cf, _): return "fav-custom:\(cf.id.uuidString)"
            case .emptyFavorite: return "empty-favorite"
            case let .filmSimulation(f, _): return "filmSim-\(f.id)"
            case let .filter(f, _): return f.id
            case let .customFilter(cf): return "custom:\(cf.id.uuidString)"
            case .importCard: return "import-card"
            case .deleteToggle: return "delete-mode-toggle"
            }
        }

        var selectionID: String? {
            switch self {
            case let .favorite(f, _), let .filmSimulation(f, _), let .filter(f, _):
                return f.id
            case let .customFavorite(cf, _), let .customFilter(cf):
                return "custom:\(cf.id.uuidString)"
            default:
                return nil
            }
        }
    }

    private var pagerItems: [PagerItem] {
        let visibleFavorites = layoutFavorites.filter { !$0.isFilmSimulationOrNone }
        let favoritedCustomFilters = customFilterManager.customFilters.filter(\.isFavorite)
        let favoriteSet = Set(visibleFavorites)
        let allNonFavoriteFilters = filterManager.allVisibleFilters.filter {
            !favoriteSet.contains($0) && !$0.isFilmSimulationOrNone
        }
        let filmSimulationFilters = FilterIdentifier.filmSimulationFilters.filter { filterManager.isFilterVisible($0) }
        let nonFavoriteCustomFilters = customFilterManager.customFilters.filter { !$0.isFavorite }

        var items: [PagerItem] = []

        // Favorites
        if !visibleFavorites.isEmpty || !favoritedCustomFilters.isEmpty {
            for (index, filter) in visibleFavorites.enumerated() {
                let isLast = index == visibleFavorites.count - 1 && favoritedCustomFilters.isEmpty
                items.append(.favorite(filter, hasDivider: isLast))
            }
            for (index, filter) in favoritedCustomFilters.enumerated() {
                let isLast = index == favoritedCustomFilters.count - 1
                items.append(.customFavorite(filter, hasDivider: isLast))
            }
        } else {
            items.append(.emptyFavorite)
        }

        // Film Simulation
        for (index, filter) in filmSimulationFilters.enumerated() {
            let isLast = index == filmSimulationFilters.count - 1
            items.append(.filmSimulation(filter, hasDivider: isLast))
        }

        // All non-favorite
        for (index, filter) in allNonFavoriteFilters.enumerated() {
            let isLast = index == allNonFavoriteFilters.count - 1
            items.append(.filter(filter, hasDivider: isLast))
        }

        // Custom
        items.append(contentsOf: nonFavoriteCustomFilters.map { .customFilter($0) })
        items.append(.importCard)

        if !customFilterManager.customFilters.isEmpty {
            items.append(.deleteToggle)
        }

        return items
    }

    var body: some View {
        GeometryReader { _ in
            Pager(page: page,
                  data: pagerItems,
                  id: \.id)
            { item in
                pagerItemView(item)
            }
            .preferredItemSize(CGSize(width: itemWidth, height: scrollViewHeight))
            .itemSpacing(14)
            .alignment(.center)
            .onPageChanged { index in
                handlePageChange(index)
            }
            .onAppear {
                syncPageToSelection()
            }
            .onChange(of: filterManager.selectedFilter) { _, _ in
                syncPageToSelection()
            }
            .onChange(of: filterManager.selectedCustomFilter?.id) { _, _ in
                syncPageToSelection()
            }
            .onChange(of: anchorTarget) { _, newTarget in
                handleAnchorTarget(newTarget)
            }
        }
        .frame(height: scrollViewHeight)
    }

    @ViewBuilder
    private func pagerItemView(_ item: PagerItem) -> some View {
        Group {
            switch item {
            case let .favorite(filter, _), let .filmSimulation(filter, _), let .filter(filter, _):
                FilterCardWithFavorite(
                    filterManager: filterManager,
                    filter: filter,
                    onFavoriteToggle: onFavoriteToggle
                )
            case let .customFavorite(filter, _), let .customFilter(filter):
                CustomFilterCard(
                    filter: filter,
                    filterManager: filterManager,
                    isDeleteMode: isDeleteMode,
                    onFavoriteToggle: onCustomFavoriteToggle
                )
            case .emptyFavorite:
                EmptyFavoritePlaceholder()
            case .importCard:
                ImportFilterCard(
                    showFileImporter: $showFileImporter,
                    showRemoteImportAlert: $showRemoteImportAlert,
                    remoteImportURL: $remoteImportURL
                )
            case .deleteToggle:
                DeleteModeToggleCard(isDeleteMode: $isDeleteMode)
            }
        }
        .frame(width: itemWidth)
        .overlay(
            Group {
                if hasDivider(item) {
                    DividerLine()
                        .frame(width: 1)
                        .offset(x: itemWidth / 2 + 7)
                }
            }
        )
    }

    private func hasDivider(_ item: PagerItem) -> Bool {
        switch item {
        case let .favorite(_, hasDivider), let .filmSimulation(_, hasDivider), let .filter(_, hasDivider), let .customFavorite(_, hasDivider):
            return hasDivider
        default:
            return false
        }
    }

    private func handlePageChange(_ index: Int) {
        let items = pagerItems
        guard index < items.count else { return }
        let item = items[index]

        if let selectionID = item.selectionID {
            applySelection(for: selectionID, triggerHaptics: true)
        }
    }

    private func syncPageToSelection() {
        let items = pagerItems
        let currentID = currentSelectionID()
        if let index = items.firstIndex(where: { $0.selectionID == currentID }),
           page.index != index
        {
            withAnimation(.easeInOut(duration: 0.25)) {
                page.update(.new(index: index))
            }
        }
    }

    private func handleAnchorTarget(_ target: String?) {
        guard let target else { return }
        let items = pagerItems

        let searchID: String
        if target == FilterGalleryView.favoriteAnchorName {
            searchID = items.first(where: { if case .favorite = $0 { return true }; if case .emptyFavorite = $0 { return true }; return false })?.id ?? ""
        } else if target == String.filterGalleryFilmSimulation.localized {
            searchID = items.first(where: { if case .filmSimulation = $0 { return true }; return false })?.id ?? ""
        } else if target == FilterGalleryView.customAnchorName {
            searchID = items.first(where: { if case .customFilter = $0 { return true }; if case .importCard = $0 { return true }; return false })?.id ?? ""
        } else {
            searchID = target
        }

        if let index = items.firstIndex(where: { $0.id == searchID || ($0.selectionID == searchID && !searchID.isEmpty) }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                page.update(.new(index: index))
            }
        }
        DispatchQueue.main.async { anchorTarget = nil }
    }

    private func currentSelectionID() -> String {
        if filterManager.selectedFilter.category == .custom,
           let customId = filterManager.selectedCustomFilter?.id.uuidString
        {
            return "custom:\(customId)"
        } else {
            return filterManager.selectedFilter.id
        }
    }

    private func applySelection(for id: String, triggerHaptics: Bool) {
        if id.hasPrefix("custom:"), let uuidString = id.split(separator: ":").last,
           let uuid = UUID(uuidString: String(uuidString)),
           let customFilter = customFilterManager.customFilters.first(where: { $0.id == uuid })
        {
            if filterManager.selectedFilter.category != .custom || filterManager.selectedCustomFilter?.id != uuid {
                if triggerHaptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                filterManager.selectCustomFilter(customFilter)
            }
        } else if let identifier = parseFilterIdentifier(from: id) {
            if filterManager.selectedFilter != identifier {
                if triggerHaptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
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
}
