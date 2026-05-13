import SwiftUI

struct FilterSettingsView: View {
    @ObservedObject var filterManager: FilterManager = .shared
    @Binding var isPresented: Bool
    @State private var detailedFilter: FilterIdentifier?

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // All filters (excluding primary color filters)
                let allFilters = FilterConfigManager.shared.getAllBuiltinIdentifiers().filter {
                    !$0.isFilmSimulation
                }
                FilterGrid(
                    filters: allFilters,
                    filterManager: filterManager,
                    detailedFilter: $detailedFilter
                )
            }
            .padding(.bottom, 80)
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.12))
        .overlay(
            HStack {
                // close button
                GlassCircleButton(iconName: "camera.fill") {
                    isPresented = false
                }
                .padding(.leading, 28)

                Spacer()

                // reset button
                GlassCircleButton(
                    iconName: "arrow.counterclockwise",
                    iconSize: 20,
                    foregroundColor: .red.opacity(0.9)
                ) {
                    filterManager.resetAllIntensities()
                }
                .padding(.trailing, 28)
            }
            .padding(.bottom, 14),
            alignment: .bottom
        )
        .sheet(item: $detailedFilter) { filter in
            FilterDetailView(filter: filter)
                .buttonStyle(.plain)
        }
    }
}

private struct FilterGrid: View {
    let filters: [FilterIdentifier]
    @ObservedObject var filterManager: FilterManager
    @Binding var detailedFilter: FilterIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // filter grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(filters, id: \.id) { filter in
                    FilterSettingItem(
                        filter: filter,
                        isSelected: filterManager.isFilterVisible(filter),
                        filterManager: filterManager,
                        onDetail: {
                            detailedFilter = filter
                        }
                    ) { isSelected in
                        if !isSelected {
                            filterManager.toggleFilterVisibility(filter)
                        } else {
                            filterManager.toggleFilterVisibility(filter)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct FilterSettingItem: View {
    let filter: FilterIdentifier
    let isSelected: Bool
    @ObservedObject var filterManager: FilterManager
    let onDetail: () -> Void
    let onToggle: (Bool) -> Void

    private var currentIntensity: Float {
        filterManager.getIntensity(for: filter)
    }

    private var defaultIntensity: Float {
        filterManager.getProcessingConfig(for: filter)?.defaultIntensity ?? 1.0
    }

    private var hasCustomIntensity: Bool {
        abs(currentIntensity - defaultIntensity) > 0.0001
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = w * 0.75
                let scale = w / 300.0

                ZStack(alignment: .topTrailing) {
                    if let displayConfig = filterManager.getDisplayConfig(for: filter) {
                        FilterCard(displayConfig: displayConfig)
                            .scaleEffect(scale)
                            .frame(width: w, height: h)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray)
                            .frame(width: w, height: h)
                    }

                    // Selected state overlay
                    if !isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.6))
                            .frame(width: w, height: h)
                    }

                    // check icon
                    Button(action: {
                        onToggle(!isSelected)
                    }) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .aspectRatio(4 / 3, contentMode: .fit)

            HStack(spacing: 4) {
                if filterManager.isLutFilter(filter) {
                    Button(action: onDetail) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Text(String(format: "%.0f%%", currentIntensity * 100))
                    .font(.system(size: 10))
                    .foregroundColor(hasCustomIntensity ? Color.accentColor : Color.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()

                    filterManager.resetIntensity(for: filter)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .foregroundColor(Color.gray)
                }
                Spacer(minLength: 0)

                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()

                    filterManager.toggleFavorite(filter)
                }) {
                    Image(systemName: filterManager.isFavorite(filter) ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .foregroundColor(filterManager.isFavorite(filter) ? Color.red : Color.gray)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 4)
        .scaleEffect(isSelected ? 1.0 : 0.95)
        .opacity(isSelected ? 1.0 : 0.6)
        .animation(
            .spring(response: 0.2, dampingFraction: 0.7),
            value: isSelected
        )
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            onToggle(!isSelected)
        }
    }
}

#Preview {
    FilterSettingsView(
        isPresented: .constant(true)
    ).background(Color(red: 0.12, green: 0.12, blue: 0.12))
}
