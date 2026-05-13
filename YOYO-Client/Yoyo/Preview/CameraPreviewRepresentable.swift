import AVFoundation
import AVKit
import CoreMotion
import Metal
import MetalPerformanceShaders
import SwiftUI

struct CameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var viewState: CameraViewState
    @ObservedObject var settingsState: CameraSettingsState
    let deviceManager = CameraDeviceManager.shared
    let sessionManager: CameraSessionManager
    let orientationManager: OrientationManager

    /// addfiltermanager
    @ObservedObject var filterManager: FilterManager = .shared

    /// addmanager
    @ObservedObject var focusManager: FocusManager

    /// addexposure manager
    @ObservedObject var exposureManager: ExposureManager

    /// add AI photo modemanager
    @ObservedObject var automationManager: CameraAutomationManager

    /// addaudiomanager
    @ObservedObject var audioManager: AudioManager

    /// add CaptureService(managementcapture)
    let captureService: CameraCaptureService
    let sampleBufferController: SampleBufferController
    let previewRenderController: PreviewRenderController

    var onCoordinatorCreated: ((Coordinator) -> Void)?

    /// initializationmethod,
    init(viewState: CameraViewState,
         settingsState: CameraSettingsState,
         sessionManager: CameraSessionManager,
         orientationManager: OrientationManager,
         focusManager: FocusManager,
         exposureManager: ExposureManager,
         automationManager: CameraAutomationManager,
         audioManager: AudioManager,
         captureService: CameraCaptureService,
         sampleBufferController: SampleBufferController,
         previewRenderController: PreviewRenderController,
         onCoordinatorCreated: ((Coordinator) -> Void)? = nil)
    {
        self.viewState = viewState
        self.settingsState = settingsState
        self.sessionManager = sessionManager
        self.orientationManager = orientationManager
        self.focusManager = focusManager
        self.exposureManager = exposureManager
        self.automationManager = automationManager
        self.audioManager = audioManager
        self.captureService = captureService
        self.sampleBufferController = sampleBufferController
        self.previewRenderController = previewRenderController
        self.onCoordinatorCreated = onCoordinatorCreated
    }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(
            sessionManager: sessionManager,
            orientationManager: orientationManager,
            settingsState: settingsState,
            previewRenderController: previewRenderController,
            sampleBufferController: sampleBufferController
        )
        view.viewState = viewState
        view.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        context.coordinator.cameraView = view
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context _: Context) {
        uiView.updateGuidelines(settingsState.guidelinesType)
        uiView.updateHDRMode(settingsState.hdrEnabled)
        uiView.aspectRatio = settingsState.effectiveAspectRatio
        uiView.viewState = viewState

        // setmanager
        uiView.setupFocusManagerIfNeeded(focusManager)

        // setexposure manager
        uiView.setupExposureManagerIfNeeded(exposureManager)

        // set AI photo mode
        uiView.setupAutomationManagerIfNeeded(automationManager)

        // setaudiomanager
        uiView.setupAudioManagerIfNeeded(audioManager)

        // set SampleBufferProvider, letCameraAutomationManagergetpreview
        automationManager.sampleBufferProvider = uiView
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        onCoordinatorCreated?(coordinator)
        return coordinator
    }

    /// Coordinator, onlyused for CameraPreviewView reference
    final class Coordinator {
        weak var cameraView: CameraPreviewView?
    }
}
