import SwiftUI

// MARK: - shutter speed slider view(horizontal)

struct ShutterSpeedSlider: View {
    @ObservedObject var exposureManager: ExposureManager
    @Binding var shutterSpeed: Double
    let range: (min: Double, max: Double)

    @State private var isUserDragging: Bool = false // whetherin progress
    @State private var rulerValue: Double = 1.0 / 60 // used for

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()

                if exposureManager.isManualShutterSpeedMode {
                    exposureManager.enableAutoShutterSpeed()
                }
            }) {
                Text("A")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(exposureManager.isManualShutterSpeedMode ? Color.white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(exposureManager.isManualShutterSpeedMode ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.3))
                    )
            }
            .padding(.trailing, 6)

            ShutterSpeedRuler(
                value: $rulerValue,
                stops: availableStops,
                onSelectionChange: { newValue in
                    shutterSpeed = newValue
                },
                onInteractionStart: {
                    isUserDragging = true
                    if !exposureManager.isManualShutterSpeedMode {
                        exposureManager.enableManualShutterSpeed()
                    }
                },
                onInteractionEnd: {
                    isUserDragging = false
                    // ensureendsync
                    shutterSpeed = rulerValue
                }
            )
        }
        .padding(.horizontal, 6)
        .onAppear {
            rulerValue = shutterSpeed
        }
        .onChange(of: shutterSpeed) { _, newValue in
            // Sync only when not dragging
            if !isUserDragging {
                rulerValue = newValue
            }
        }
        .onChange(of: exposureManager.currentShutterSpeed) { _, newValue in
            // Update the displayed value to the camera's current shutter speed only in auto mode and when not dragging
            if !exposureManager.isManualShutterSpeedMode, !isUserDragging {
                rulerValue = newValue
            }
        }
    }

    /// Filter available shutter speed stops according to the range supported by the camera
    private var availableStops: [Double] {
        CameraParameterFormatter.standardShutterSpeedStops.filter { $0 >= range.min && $0 <= range.max }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        HStack {
            ShutterSpeedSlider(
                exposureManager: ExposureManager.shared,
                shutterSpeed: .constant(1.0 / 60.0),
                range: (min: 1.0 / 8000.0, max: 1.0)
            )

            Image(systemName: "xmark")
                .font(.system(size: 12))
                .foregroundColor(Color.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                )
        }
    }
}
