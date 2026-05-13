import Combine
import SwiftUI

/// camera preview view model, managementpreviewrelatedstatebusiness logic
@MainActor
final class CameraPreviewViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var previewFrame: CGRect = .zero
    @Published var isPreviewReady: Bool = false
    @Published var isParameterDrawerExpanded: Bool = false
    @Published var pendingInspirationImage: UIImage? = nil

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    let viewState: CameraViewState
    let settingsState: CameraSettingsState
    let cameraManagers: CameraManagersContainer
    let automationManager: CameraAutomationManager
    let captureService: CameraCaptureService
    let sampleBufferController: SampleBufferController
    let frameProvider: PreviewFrameProvider

    // MARK: - Computed Properties

    var bottomControlHeight: CGFloat {
        CameraLayoutConfig.bottomControlHeight
    }

    func availableHeight(for geometry: GeometryProxy) -> CGFloat {
        CameraLayoutConfig.availableHeight(for: geometry, bottomControlHeight: bottomControlHeight)
    }

    func availableWidth(for geometry: GeometryProxy) -> CGFloat {
        CameraLayoutConfig.availableWidth(for: geometry)
    }

    // MARK: - Initialization

    init(
        viewState: CameraViewState,
        settingsState: CameraSettingsState,
        cameraManagers: CameraManagersContainer,
        automationManager: CameraAutomationManager
    ) {
        self.viewState = viewState
        self.settingsState = settingsState
        self.cameraManagers = cameraManagers
        self.automationManager = automationManager
        captureService = cameraManagers.captureService
        sampleBufferController = cameraManagers.sampleBufferController
        frameProvider = cameraManagers.previewFrameProvider

        setupBindings()
    }

    private func setupBindings() {
        NotificationCenter.default.publisher(for: .cameraUserAction)
            .compactMap { $0.userInfo?[CameraNotificationKeys.action] as? CameraViewState.UserAction }
            .filter { $0 == .requestAIInspiration }
            .sink { [weak self] _ in
                self?.triggerAIInspiration()
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout Calculations

    func calculatePreviewFrame(for geometry: GeometryProxy) -> CGRect {
        let viewSize = geometry.size
        let previewAspectRatioValue = settingsState.effectiveAspectRatio
        let viewAspectRatio = viewSize.width / viewSize.height

        var previewFrame = CGRect.zero

        if viewAspectRatio > previewAspectRatioValue {
            let previewWidth = viewSize.height * previewAspectRatioValue
            let xOffset = (viewSize.width - previewWidth) / 2
            previewFrame = CGRect(
                x: xOffset,
                y: 0,
                width: previewWidth,
                height: viewSize.height
            )
        } else {
            let previewHeight = viewSize.width / previewAspectRatioValue
            let yOffset = (viewSize.height - previewHeight) / 2
            previewFrame = CGRect(
                x: 0,
                y: yOffset,
                width: viewSize.width,
                height: previewHeight
            )
        }

        self.previewFrame = previewFrame
        return previewFrame
    }

    // MARK: - Overlay Visibility Logic

    func shouldShowInspirationOverlay() -> Bool {
        cameraManagers.inspirationManager.isShowingInspirations
    }

    func shouldShowTimerOverlay() -> Bool {
        settingsState.timerCaptureEnabled
    }

    // MARK: - Actions

    func hideInspiration() {
        cameraManagers.inspirationManager.clearInspirations()
    }

    func triggerAIInspiration() {
        AuthManager.shared.checkProAccess { [weak self] in
            guard let self else { return }

            let imageToUse = self.pendingInspirationImage ?? self.frameProvider.latestImage()

            withAnimation(.spring()) {
                self.pendingInspirationImage = nil // Clear after use
            }

            Task { @MainActor in
                await self.cameraManagers.inspirationManager.requestAIInspirations(from: imageToUse)
            }
        }
    }

    func prepareAIInspiration() {
        pendingInspirationImage = frameProvider.latestImage()
    }

    func onActualPhotoCapture() {
        // triggertake a photologic
        captureService.startCapture()
    }
}
