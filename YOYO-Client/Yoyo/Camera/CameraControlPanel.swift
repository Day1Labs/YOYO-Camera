import SwiftUI

// MARK: - Design Constants

private enum CameraControlPanelDesign {
    static let buttonColor = Color.white.opacity(0.12)
    static let buttonActiveColor = Color.white
    static let iconActiveColor = Color.black
    static let cornerRadius: CGFloat = 38
    static let buttonSize: CGFloat = 64
    static let expandedButtonWidth: CGFloat = 142
    static let spacing: CGFloat = 14
    static let iconSize: CGFloat = 22
}

// MARK: - CameraControlPanel

struct CameraControlPanel: View {
    @ObservedObject var settingsState: CameraSettingsState
    let viewState: CameraViewState
    let sessionManager: CameraSessionManager
    let automationManager: CameraAutomationManager?
    @EnvironmentObject var permissionManager: PermissionManager
    let orientationManager: OrientationManager

    @State private var showingControlPanel = false

    var body: some View {
        Button {
            showingControlPanel = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
        }
        .fullScreenCover(isPresented: $showingControlPanel) {
            CameraControlPanelOverlay(
                settingsState: settingsState,
                viewState: viewState,
                sessionManager: sessionManager,
                permissionManager: permissionManager,
                isPresented: $showingControlPanel
            )
            .presentationBackground(.clear)
            .statusBarHidden(true)
            .transaction { $0.disablesAnimations = true }
        }
        .transaction { $0.disablesAnimations = true }
    }
}

// MARK: - Control Panel Overlay

private struct CameraControlPanelOverlay: View {
    @ObservedObject var settingsState: CameraSettingsState
    @ObservedObject var viewState: CameraViewState
    let sessionManager: CameraSessionManager
    let permissionManager: PermissionManager
    @Binding var isPresented: Bool

    @State private var isVisible = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Transparent background; tap to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissPanel()
                }

            // Control panel
            if isVisible {
                CameraControlPanelContent(
                    settingsState: settingsState,
                    viewState: viewState,
                    sessionManager: sessionManager,
                    permissionManager: permissionManager,
                    dismissAction: { dismissPanel() },
                    openSettings: {
                        dismissPanel()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewState.showingSettings = true
                        }
                    }
                )
                .trackScreen(name: "CameraControlPanel")
                .padding(.top, CameraLayoutConfig.topMenuHeight)
                .padding(.trailing, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.01)) // Almost transparent but still tappable
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                isVisible = true
            }
        }
    }

    private func dismissPanel() {
        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }
}

// MARK: - Control Panel View

private struct CameraControlPanelContent: View {
    @ObservedObject var settingsState: CameraSettingsState
    @ObservedObject var viewState: CameraViewState
    let sessionManager: CameraSessionManager
    let permissionManager: PermissionManager
    let dismissAction: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            VStack(spacing: CameraControlPanelDesign.spacing) {
                // First row: capture mode and front/back camera
                HStack(spacing: CameraControlPanelDesign.spacing) {
                    CaptureModeButton(settingsState: settingsState)
                    CameraRotateButton(sessionManager: sessionManager, settingsState: settingsState)
                }

                // Second row: flash, timer, and Live Photo/stabilization
                HStack(spacing: CameraControlPanelDesign.spacing) {
                    FlashTorchButton(settingsState: settingsState)
                    TimerCycleButton(settingsState: settingsState)
                    LivePhotoStabButton(settingsState: settingsState)
                }

                // Third row: GPS, save original, and settings
                HStack(spacing: CameraControlPanelDesign.spacing) {
                    // GPS button
                    CameraControlPanelButton(
                        icon: "location.fill",
                        isActive: settingsState.saveGPSEnabled
                    ) {
                        settingsState.toggleGPSSetting()
                        AnalyticsManager.shared.log(.settingsAction(action: "toggle_gps_\(settingsState.saveGPSEnabled)"))
                    }

                    // Save-original button
                    CameraControlPanelButton(
                        icon: "rectangle.on.rectangle.fill",
                        isActive: settingsState.saveOriginalEnabled
                    ) {
                        settingsState.toggleSetting(\.saveOriginalEnabled)
                        AnalyticsManager.shared.log(.settingsAction(action: "toggle_save_original_\(settingsState.saveOriginalEnabled)"))
                    }

                    // More-settings button
                    CameraControlPanelButton(icon: "gearshape.fill", isActive: false) {
                        settingsState.generateHapticFeedback()
                        openSettings()
                    }
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: CameraControlPanelDesign.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            }
        }
    }
}

// MARK: - Flash & Torch Button

private struct FlashTorchButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var flashIcon: String {
        if settingsState.currentCaptureMode == .movie {
            return "flashlight.on.fill"
        }
        return "bolt.fill"
    }

    private var isActive: Bool {
        if settingsState.currentCaptureMode == .movie {
            return settingsState.torchEnabled
        }
        return settingsState.flashMode == .on
    }

    var body: some View {
        CameraControlPanelButton(icon: flashIcon, isActive: isActive) {
            settingsState.generateHapticFeedback()
            if settingsState.currentCaptureMode == .movie {
                settingsState.torchEnabled.toggle()
                CameraDeviceManager.shared.setTorch(enabled: settingsState.torchEnabled)
            } else {
                settingsState.flashMode = (settingsState.flashMode == .on) ? .off : .on
            }
            AnalyticsManager.shared.log(.settingsAction(action: "toggle_flash_torch_\(isActive)"))
        }
    }
}

// MARK: - Capture Mode Button

private struct CaptureModeButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var icon: String {
        settingsState.currentCaptureMode == .movie ? "video.fill" : "camera.fill"
    }

    private var modeValue: String {
        settingsState.currentCaptureMode.rawValue
    }

    var body: some View {
        Button {
            settingsState.generateHapticFeedback()
            settingsState.currentCaptureMode = (settingsState.currentCaptureMode == .movie) ? .photo : .movie
            AnalyticsManager.shared.log(.settingsAction(action: "switch_mode_\(settingsState.currentCaptureMode)"))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: CameraControlPanelDesign.iconSize, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("camera_settings_capture_mode", comment: "Shooting Mode"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(modeValue)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: CameraControlPanelDesign.expandedButtonWidth, height: CameraControlPanelDesign.buttonSize, alignment: .leading)
            .background(CameraControlPanelDesign.buttonColor)
            .clipShape(RoundedRectangle(cornerRadius: CameraControlPanelDesign.buttonSize / 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera Rotate Button

private struct CameraRotateButton: View {
    let sessionManager: CameraSessionManager
    @ObservedObject var settingsState: CameraSettingsState

    var body: some View {
        CameraControlPanelButton(icon: "camera.rotate", isActive: false) {
            settingsState.generateHapticFeedback()
            sessionManager.switchCameraPosition()
            AnalyticsManager.shared.log(.settingsAction(action: "switch_camera"))
        }
    }
}

// MARK: - LivePhoto & Stabilization Button

private struct LivePhotoStabButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var icon: String {
        if settingsState.currentCaptureMode == .movie {
            return "water.waves"
        }
        return "livephoto"
    }

    private var isActive: Bool {
        if settingsState.currentCaptureMode == .movie {
            return settingsState.stabilizationEnabled
        }
        return settingsState.currentCaptureMode == .livePhoto
    }

    var body: some View {
        CameraControlPanelButton(icon: icon, isActive: isActive) {
            settingsState.generateHapticFeedback()
            if settingsState.currentCaptureMode == .movie {
                settingsState.stabilizationEnabled.toggle()
            } else {
                if settingsState.currentCaptureMode == .livePhoto {
                    settingsState.currentCaptureMode = .photo
                } else {
                    settingsState.currentCaptureMode = .livePhoto
                }
            }
            AnalyticsManager.shared.log(.settingsAction(action: "toggle_live_stab_\(isActive)"))
        }
    }
}

// MARK: - Control Panel Button

private struct CameraControlPanelButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: CameraControlPanelDesign.iconSize, weight: .medium))
                .foregroundColor(isActive ? CameraControlPanelDesign.iconActiveColor : .white)
                .frame(width: CameraControlPanelDesign.buttonSize, height: CameraControlPanelDesign.buttonSize)
                .background(isActive ? CameraControlPanelDesign.buttonActiveColor : CameraControlPanelDesign.buttonColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timer Cycle Button (Cycle Through Timer Options)

private struct TimerCycleButton: View {
    @ObservedObject var settingsState: CameraSettingsState

    private var timerIcon: String {
        if !settingsState.timerCaptureEnabled {
            return "timer"
        }
        switch settingsState.timerCaptureSeconds {
        case 5: return "gobackward.5"
        case 10: return "gobackward.10"
        case 30: return "gobackward.30"
        default: return "timer"
        }
    }

    var body: some View {
        Button {
            cycleTimer()
        } label: {
            ZStack {
                Image(systemName: timerIcon)
                    .font(.system(size: CameraControlPanelDesign.iconSize, weight: .medium))
                    .foregroundColor(settingsState.timerCaptureEnabled ? CameraControlPanelDesign.iconActiveColor : .white)
            }
            .frame(width: CameraControlPanelDesign.buttonSize, height: CameraControlPanelDesign.buttonSize)
            .background(settingsState.timerCaptureEnabled ? CameraControlPanelDesign.buttonActiveColor : CameraControlPanelDesign.buttonColor)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func cycleTimer() {
        settingsState.generateHapticFeedback()

        if !settingsState.timerCaptureEnabled {
            // Off -> 5s
            settingsState.timerCaptureEnabled = true
            settingsState.timerCaptureSeconds = 5
        } else {
            switch settingsState.timerCaptureSeconds {
            case 5:
                settingsState.timerCaptureSeconds = 10
            case 10:
                settingsState.timerCaptureSeconds = 30
            case 30:
                // 30s -> Off
                settingsState.timerCaptureEnabled = false
            default:
                settingsState.timerCaptureEnabled = false
            }
        }

        let timerValue = settingsState.timerCaptureEnabled ? settingsState.timerCaptureSeconds : 0
        AnalyticsManager.shared.log(.settingsAction(action: "cycle_timer_\(timerValue)"))
    }
}

// MARK: - Preview

#Preview {
    let settingsState = CameraSettingsState.shared
    let viewState = CameraViewState()
    let permissionManager = PermissionManager.shared
    let orientationManager = OrientationManager.shared
    let sessionManager = CameraSessionManager.shared

    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            HStack {
                Spacer()
                CameraControlPanel(
                    settingsState: settingsState,
                    viewState: viewState,
                    sessionManager: sessionManager,
                    automationManager: nil,
                    orientationManager: orientationManager
                )
                .environmentObject(permissionManager)
                .padding()
            }
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
