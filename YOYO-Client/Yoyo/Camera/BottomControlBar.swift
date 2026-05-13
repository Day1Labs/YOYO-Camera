import Combine
import SwiftUI

// MARK: - Bottom Control Bar

/// Bottom control bar
struct BottomControlBar: View {
    let latestPhoto: PhotoAsset?
    let managers: CameraManagersContainer

    // Helper properties for easier access
    private var viewState: CameraViewState { managers.viewState }
    private var settingsState: CameraSettingsState { managers.settingsState }

    var body: some View {
        VStack {
            // Control row - redesigned to keep the capture button centered on screen
            ZStack {
                // 1. Capture button - always centered on screen
                // Use `GeometryReader` to ensure perfect centering, or rely on `ZStack` center alignment directly (most reliable)
                CaptureButton(
                    settingsState: settingsState,
                    action: { managers.captureService.triggerShutterAction() }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                // Ensure the tap area is not blocked
                .zIndex(1)

                // 2. Control buttons on the left and right sides
                HStack(spacing: 0) {
                    // Gallery button - left side
                    PhotoGalleryButton(
                        latestPhoto: latestPhoto,
                        rotation: 0, // Rotation is handled by `rotationEffect`
                        onTap: {
                            triggerLightImpact()
                            viewState.showingPhotoGallery = true
                        }
                    )
                    .equatable()
                    .rotationEffect(.degrees(viewState.rotation))
                    .animation(.easeInOut(duration: 0.3), value: viewState.rotation)

                    Spacer()

                    // Filter switch button - right side
                    FilterGalleryButton(
                        viewState: viewState,
                        rotation: 0 // Rotation is handled by `rotationEffect`
                    )
                    .rotationEffect(.degrees(viewState.rotation))
                    .animation(.easeInOut(duration: 0.3), value: viewState.rotation)
                }
                .padding(.horizontal, CameraControlDesign.horizontalPadding)
                // Ensure the side buttons do not block the center capture button
                // The capture button is typically larger (~80pt), while side buttons are ~40-50pt
                // With additional padding (~20-30pt), they should not overlap unless the screen is extremely narrow
            }
            .frame(maxWidth: .infinity)
        }
    }

    @MainActor
    private func triggerLightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Filter Switch Button

/// Filter switch button
struct FilterGalleryButton: View {
    @ObservedObject var filterManager: FilterManager = .shared
    let viewState: CameraViewState
    let rotation: Double

    private var buttonHeight: CGFloat {
        CameraControlDesign.sideButtonSize
    }

    private var buttonWidth: CGFloat {
        CameraControlDesign.filterButtonWidth
    }

    private var cardScale: CGFloat {
        buttonWidth / 300.0
    }

    var body: some View {
        Button(action: {
            triggerLightImpact()
            if !viewState.showingFilterGallery {
                viewState.showingFilterGallery = true
            }
        }) {
            ZStack {
                if filterManager.selectedFilter.category == .custom, let customFilter = filterManager.selectedCustomFilter {
                    customFilterPlaceholder(name: customFilter.name)
                } else if let displayConfig = filterManager.getDisplayConfig(for: filterManager.selectedFilter) {
                    filterCardWithOverlay(displayConfig: displayConfig)
                } else {
                    placeholderView
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .frame(width: buttonWidth, height: buttonHeight)
    }

    @MainActor
    private func triggerLightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private func customFilterPlaceholder(name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.12))

            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .frame(width: buttonWidth, height: buttonHeight)
    }

    @ViewBuilder
    private func filterCardWithOverlay(displayConfig: FilterDisplayConfig) -> some View {
        // Base card
        FilterCard(displayConfig: displayConfig)
            .scaleEffect(cardScale)
            .frame(width: buttonWidth, height: buttonHeight)
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .frame(width: buttonWidth, height: buttonHeight)
    }
}
