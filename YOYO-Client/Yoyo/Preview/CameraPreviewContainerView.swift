import AVFoundation
import Combine
import SwiftUI

/// camera preview container view, and Container logic
struct CameraPreviewContainerView: View {
    @StateObject private var viewModel: CameraPreviewViewModel

    // state, ViewModel
    @ObservedObject var viewState: CameraViewState
    @ObservedObject var settingsState: CameraSettingsState
    @ObservedObject var inspirationManager: InspirationManager

    @AppStorage("isDeveloperMode") private var isDeveloperMode: Bool = false

    private let geometry: GeometryProxy
    private let isParameterDrawerExpanded: Bool
    private let onCoordinatorCreated: (CameraPreviewRepresentable.Coordinator) -> Void

    @State private var captureState: CaptureState = .idle
    @State private var recordingStartTime: Date?
    @State private var lastZoomFactor: Double = 1.0
    @State private var hideLensButtonTask: Task<Void, Never>? = nil
    @State private var zoomCancellable: AnyCancellable? = nil

    init(
        geometry: GeometryProxy,
        viewState: CameraViewState,
        settingsState: CameraSettingsState,
        cameraManagers: CameraManagersContainer,
        automationManager: CameraAutomationManager,
        isParameterDrawerExpanded: Bool,
        onCoordinatorCreated: @escaping (CameraPreviewRepresentable.Coordinator) -> Void
    ) {
        self.geometry = geometry
        self.viewState = viewState
        self.settingsState = settingsState
        inspirationManager = cameraManagers.inspirationManager
        self.isParameterDrawerExpanded = isParameterDrawerExpanded
        _viewModel = StateObject(wrappedValue: CameraPreviewViewModel(
            viewState: viewState,
            settingsState: settingsState,
            cameraManagers: cameraManagers,
            automationManager: automationManager
        ))
        self.onCoordinatorCreated = onCoordinatorCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            // top
            Rectangle()
                .fill(Color.clear)
                .frame(height: CameraLayoutConfig.topMenuHeight)

            // camerapreview
            cameraPreviewContent
                .frame(
                    maxWidth: viewModel.availableWidth(for: geometry),
                    maxHeight: viewModel.availableHeight(for: geometry)
                )

            // bottom
            Rectangle()
                .fill(Color.clear)
                .frame(height: viewModel.bottomControlHeight)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.settingsState.effectiveAspectRatio)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isParameterDrawerExpanded)
        .onChange(of: isParameterDrawerExpanded) { _, newValue in
            viewModel.isParameterDrawerExpanded = newValue
        }
        .onAppear {
            viewModel.isParameterDrawerExpanded = isParameterDrawerExpanded
            // auto
            scheduleLensButtonHide()
            // zoom
            setupZoomObserver()
        }
        .onDisappear {
            // Cancel the pending hide task
            hideLensButtonTask?.cancel()
            // zoomobserve
            zoomCancellable?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCaptureStateChanged)) { notification in
            if let newState = notification.userInfo?[CameraNotificationKeys.captureState] as? CaptureState {
                captureState = newState
                handleCaptureStateChange(newState)
            }
        }
        .sheet(isPresented: $inspirationManager.showLoginSheet) {
            SettingsView()
                .environmentObject(settingsState)
        }
    }

    private func handleCaptureStateChange(_ newState: CaptureState) {
        // recording
        if newState == .capturing, viewModel.settingsState.currentCaptureMode == .movie {
            startRecordingTimer()
        } else if newState != .capturing {
            stopRecordingTimer()
        }
    }

    private func startRecordingTimer() {
        recordingStartTime = Date()
    }

    private func stopRecordingTimer() {
        recordingStartTime = nil
    }

    // MARK: - Zoom Observer

    /// setzoom, observezoomgesture
    private func setupZoomObserver() {
        let zoomThreshold = 0.01
        zoomCancellable = ZoomManager.shared.$deviceZoomFactor
            .receive(on: DispatchQueue.main)
            .sink { [lastZoomFactor] newZoom in
                // zoomgesture - zoombutton
                if abs(newZoom - lastZoomFactor) > zoomThreshold {
                    showLensButtonTemporarily()
                }
            }
    }

    // MARK: - Lens Switch Button Auto-hide

    /// auto(3 seconds)
    private func scheduleLensButtonHide() {
        // Cancel the previous task
        hideLensButtonTask?.cancel()

        hideLensButtonTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            // checkwhether
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                viewState.showLensSwitchButton = false
            }
        }
    }

    /// temporarybutton, thenauto
    private func showLensButtonTemporarily() {
        // Cancel the previous hide task
        hideLensButtonTask?.cancel()

        // button
        if !viewState.showLensSwitchButton {
            withAnimation(.easeIn(duration: 0.2)) {
                viewState.showLensSwitchButton = true
            }
        }

        // Restart the hide timer
        scheduleLensButtonHide()
    }

    @ViewBuilder
    private var cameraPreviewContent: some View {
        CameraPreviewRepresentable(
            viewState: viewModel.viewState,
            settingsState: viewModel.settingsState,
            sessionManager: viewModel.cameraManagers.sessionManager,
            orientationManager: viewModel.cameraManagers.orientationManager,
            focusManager: viewModel.cameraManagers.focusManager,
            exposureManager: viewModel.cameraManagers.exposureManager,
            automationManager: viewModel.automationManager,
            audioManager: viewModel.cameraManagers.audioManager,
            captureService: viewModel.captureService,
            sampleBufferController: viewModel.sampleBufferController,
            previewRenderController: viewModel.cameraManagers.previewRenderController,
            onCoordinatorCreated: { coordinator in
                Task { @MainActor in
                    onCoordinatorCreated(coordinator)
                }
            }
        )
        .aspectRatio(viewModel.settingsState.effectiveAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(focusOverlay)
        .overlay { rotatingOverlayContent }
        .overlay(alignment: .bottom) {
            if viewState.showLensSwitchButton,
               viewModel.pendingInspirationImage == nil,
               !viewState.isInspirationMaximized
            {
                LensSwitchButton(
                    zoomManager: CameraDeviceManager.shared.zoomManager,
                    viewState: viewModel.viewState,
                    currentCaptureMode: viewModel.settingsState.currentCaptureMode
                )
                .padding(.bottom, 9)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.pendingInspirationImage == nil, !viewState.isInspirationMaximized {
                InspirationEntryButton(
                    isShowingInspiration: inspirationManager.isShowingInspirations,
                    rotation: viewModel.viewState.rotation,
                    onTap: {
                        if inspirationManager.isShowingInspirations {
                            viewModel.hideInspiration()
                        } else {
                            viewModel.prepareAIInspiration()
                        }
                    }
                )
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .overlay { pendingInspirationPreviewOverlay }
        .onChange(of: viewModel.viewState.rotation) { _, _ in
            // no-op to keep view updated; rotation already drives overlay
        }
    }

    @ViewBuilder
    private var pendingInspirationPreviewOverlay: some View {
        if let image = viewModel.pendingInspirationImage {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.6))
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.pendingInspirationImage = nil
                    }

                VStack(spacing: 24) {
                    Text(String.aiInspirationPreviewTapToGet.localized)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 40)

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.horizontal, 40)
                        .shadow(color: .black.opacity(0.3), radius: 20)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                viewModel.triggerAIInspiration()
                            }
                        }

                    Text(String.aiInspirationPreviewCancelHint.localized)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 40)
                }
                .rotationEffect(.degrees(viewModel.viewState.rotation))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.viewState.rotation)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    @ViewBuilder
    private var rotatingOverlayContent: some View {
        ZStack {
            timerOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(topStatusOverlay, alignment: .top)
        .overlay(inspirationOverlay, alignment: .leading)
    }

    // MARK: - Overlay Views

    @ViewBuilder
    private var topStatusOverlay: some View {
        VStack(spacing: 12) {
            // recording
            if captureState == .capturing, viewModel.settingsState.currentCaptureMode == .movie, let startTime = recordingStartTime {
                RecordingTimerView(startTime: startTime)
                    .transition(.opacity)
            }

            // Toast
            if let toast = viewModel.viewState.currentToast {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toast.id)
            }
        }
        .padding(.top, 10)
        .animation(.easeInOut(duration: 0.2), value: captureState == .capturing)
    }

    @ViewBuilder
    private var inspirationOverlay: some View {
        if viewModel.shouldShowInspirationOverlay() {
            InspirationOverlay(
                inspirationManager: viewModel.cameraManagers.inspirationManager,
                orientationManager: viewModel.cameraManagers.orientationManager,
                viewState: viewModel.viewState,
                onHideInspiration: viewModel.hideInspiration
            )
        }
    }

    @ViewBuilder
    private var focusOverlay: some View {
        FocusOverlayView(
            focusManager: viewModel.cameraManagers.focusManager,
            exposureManager: viewModel.cameraManagers.exposureManager
        )
    }

    @ViewBuilder
    private var timerOverlay: some View {
        if viewModel.shouldShowTimerOverlay() {
            TimerCountdownView(
                countdownSeconds: viewModel.settingsState.timerCaptureSeconds,
                isActive: captureState == .countingDown,
                onCountdownFinished: viewModel.onActualPhotoCapture
            )
        }
    }
}

private struct RotatingOverlayContainer<Content: View>: View {
    let rotation: Double
    private let content: () -> Content

    init(rotation: Double, @ViewBuilder content: @escaping () -> Content) {
        self.rotation = rotation
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let effectiveSize = Self.effectiveSize(for: proxy.size, rotation: rotation)

            content()
                .frame(width: effectiveSize.width, height: effectiveSize.height)
                .rotationEffect(.degrees(rotation))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private static func effectiveSize(for size: CGSize, rotation: Double) -> CGSize {
        guard shouldSwapDimensions(rotation: rotation) else {
            return size
        }
        return CGSize(width: size.height, height: size.width)
    }

    private static func shouldSwapDimensions(rotation: Double) -> Bool {
        let normalized = abs(rotation.truncatingRemainder(dividingBy: 180))
        return abs(normalized - 90) < 0.1
    }
}

#Preview {
    GeometryReader { geometry in
        CameraPreviewContainerView(
            geometry: geometry,
            viewState: CameraViewState(),
            settingsState: CameraSettingsState.shared,
            cameraManagers: CameraManagersContainer(),
            automationManager: CameraAutomationManager.shared,
            isParameterDrawerExpanded: false,
            onCoordinatorCreated: { _ in }
        )
    }
}
