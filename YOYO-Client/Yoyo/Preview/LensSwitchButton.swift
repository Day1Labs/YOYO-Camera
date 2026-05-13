import AVFoundation
import SwiftUI

/// Lens switch button - displayed at the bottom center of the preview
struct LensSwitchButton: View {
    @ObservedObject var zoomManager: ZoomManager
    @ObservedObject var viewState: CameraViewState
    let currentCaptureMode: CameraCaptureMode
    let deviceManager = CameraDeviceManager.shared

    var body: some View {
        HStack(spacing: 0) {
            if deviceManager.getUltraWideCamera() != nil {
                LensOptionButton(
                    type: .builtInUltraWideCamera,
                    iconName: "camera.macro",
                    focalLengthText: getFocalLengthText(for: .ultraWide),
                    isSelected: isSelected(.builtInUltraWideCamera),
                    currentZoom: zoomManager.deviceZoomFactor,
                    rotation: viewState.rotation
                ) {
                    switchTo(.builtInUltraWideCamera)
                }
            }

            if deviceManager.getWideAngleCamera() != nil {
                LensOptionButton(
                    type: .builtInWideAngleCamera,
                    iconName: "tree.fill",
                    focalLengthText: getFocalLengthText(for: .backWide),
                    isSelected: isSelected(.builtInWideAngleCamera),
                    currentZoom: zoomManager.deviceZoomFactor,
                    rotation: viewState.rotation
                ) {
                    switchTo(.builtInWideAngleCamera)
                }
            }

            if deviceManager.getTelephotoCamera() != nil {
                LensOptionButton(
                    type: .builtInTelephotoCamera,
                    iconName: "mountain.2.fill",
                    focalLengthText: getFocalLengthText(for: .telephoto),
                    isSelected: isSelected(.builtInTelephotoCamera),
                    currentZoom: zoomManager.deviceZoomFactor,
                    rotation: viewState.rotation
                ) {
                    switchTo(.builtInTelephotoCamera)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .onChange(of: currentCaptureMode) { _, _ in
            zoomManager.resetZoom()
        }
    }

    private func isSelected(_ type: AVCaptureDevice.DeviceType) -> Bool {
        deviceManager.getCurrentBackDeviceType() == type
    }

    private func switchTo(_ type: AVCaptureDevice.DeviceType) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        zoomManager.switchToDevice(type)
    }

    private func getFocalLengthText(for type: CameraDeviceType) -> String {
        let spec = deviceManager.currentDeviceSpec
        let fl: Double?
        switch type {
        case .ultraWide: fl = spec.ultraWideFocalLength
        case .backWide: fl = spec.wideFocalLength
        case .telephoto: fl = spec.telephotoFocalLength
        default: fl = spec.wideFocalLength
        }

        if let val = fl {
            return "\(Int(val))mm"
        }
        return ""
    }
}

struct LensOptionButton: View {
    let type: AVCaptureDevice.DeviceType
    let iconName: String
    let focalLengthText: String
    let isSelected: Bool
    let currentZoom: Double
    let rotation: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background Highlight for Selected State - Glass Style
                if isSelected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                        .environment(\.colorScheme, .dark)
                }

                VStack(spacing: 0) {
                    if isSelected {
                        // Selected State: Show Zoom Factor (e.g., 1.5x)
                        HStack(spacing: 1) {
                            Text(String(format: "%.1f", currentZoom))
                                .font(.system(size: 14, weight: .medium))
                            Text("x")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                    } else {
                        // Unselected State: Show Icon + Focal Length
                        VStack(spacing: 2) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .medium))
                                .frame(height: 14)
                            Text(focalLengthText)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                    }
                }
                .rotationEffect(.degrees(rotation))
            }
            .frame(width: 40, height: 40) // Visual size
            .contentShape(Rectangle()) // Ensure entire area is tappable even if transparent
            .frame(width: 58, height: 50) // Expand touch area to eliminate gaps (40 visual + 18 gap)
            .contentShape(Rectangle()) // Ensure expanded area is tappable
        }
        .buttonStyle(PlainButtonStyle())
    }
}
