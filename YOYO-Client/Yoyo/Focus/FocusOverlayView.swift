import SwiftUI

// MARK: - camera overlay view

struct FocusOverlayView: View {
    @ObservedObject var focusManager: FocusManager
    @ObservedObject var exposureManager: ExposureManager
    @State private var showExposureSlider = false

    var body: some View {
        ZStack {
            // focus indicator
            if focusManager.isShowingFocusIndicator {
                FocusIndicatorView(
                    focusState: focusManager.focusState,
                    focusMode: focusManager.focusMode,
                    position: focusManager.focusPoint,
                    isLocked: focusManager.isFocusLocked
                )
                // Avoid using CGPoint as Hashable (only iOS 18+). Use a stable String identifier instead.
                .id("\(focusManager.focusPoint.x),\(focusManager.focusPoint.y)")
            }

            // exposure indicator
            if exposureManager.isShowingExposureIndicator {
                ExposureIndicatorView(
                    position: exposureManager.exposurePoint,
                    exposureCompensation: exposureManager.exposureCompensation,
                    isLocked: focusManager.isFocusLocked,
                    isExposureOnlyLocked: exposureManager.isExposureLocked
                )
                .onTapGesture {
                    if exposureManager.canAdjustExposure {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showExposureSlider.toggle()
                        }
                    }
                }
            }
        }
        .onTapGesture {
            // Click another area to hide the exposure slider
            if showExposureSlider {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showExposureSlider = false
                }
            }
        }
        .onChange(of: focusManager.isFocusLocked) { _, isLocked in
            if !isLocked {
                showExposureSlider = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        FocusOverlayView(
            focusManager: FocusManager.shared,
            exposureManager: ExposureManager.shared
        )
    }
}
