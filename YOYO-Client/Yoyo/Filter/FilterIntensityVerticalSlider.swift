import SwiftUI

// MARK: - Filter strength vertical slider component (iOS volume bar style)

struct FilterIntensityVerticalSlider: View {
    @ObservedObject var filterManager: FilterManager = .shared
    @Binding var currentIntensity: Float
    var onIntensityChange: ((Float) -> Void)?
    @State private var isDragging: Bool = false

    private var isSmallScreen: Bool {
        UIScreen.main.bounds.width < 395
    }

    private var sliderHeight: CGFloat {
        isSmallScreen ? 76 : 88
    }

    private let sliderWidth: CGFloat = 30
    private let minValue: Float
    private let iconName: String

    init(currentIntensity: Binding<Float>, minValue: Float = FilterIntensityConstants.minIntensity, iconName: String = "camera.filters", onIntensityChange: ((Float) -> Void)? = nil) {
        _currentIntensity = currentIntensity
        self.minValue = minValue
        self.iconName = iconName
        self.onIntensityChange = onIntensityChange
    }

    var body: some View {
        VStack(spacing: 0) {
            // iOS volume bar style slider
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // background track
                    RoundedRectangle(cornerRadius: sliderWidth / 2)
                        .fill(Color.black.opacity(0.15))
                        .frame(width: sliderWidth)

                    // Fill track (from bottom up, adjust range to minValue-maxIntensity)
                    RoundedRectangle(cornerRadius: sliderWidth / 2)
                        .fill(Color.white)
                        .frame(
                            width: sliderWidth,
                            height: max(sliderWidth, geometry.size.height * CGFloat((currentIntensity - minValue) / (FilterIntensityConstants.maxIntensity - minValue)))
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle()) // Expand click area
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }

                            // Calculate new intensity values ​​(starting at the bottom and increasing upwards)
                            let newValue = FilterIntensityConstants.maxIntensity - Float(value.location.y / geometry.size.height)
                            let clampedValue = max(minValue, min(FilterIntensityConstants.maxIntensity, newValue))

                            // Haptic feedback every 10% (adjustable range to minValue-maxIntensity)
                            let range = FilterIntensityConstants.maxIntensity - minValue
                            let oldPercentage = Int((currentIntensity - minValue) / range * 10)
                            let newPercentage = Int((clampedValue - minValue) / range * 10)
                            if oldPercentage != newPercentage {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }

                            currentIntensity = clampedValue
                            if let onIntensityChange {
                                onIntensityChange(clampedValue)
                            } else {
                                filterManager.setIntensity(clampedValue, for: filterManager.selectedFilter)
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            print("Filter intensity set to: \(currentIntensity)")
                        }
                )
            }
            .frame(width: sliderWidth, height: sliderHeight)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(alignment: .bottom) {
            // The filter icon is overlaid on the top layer
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black.opacity(0.5))
                .padding(.bottom, 4)
        }
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
    }
}
