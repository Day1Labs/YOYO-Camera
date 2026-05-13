import AVFoundation
import Combine
import CoreImage
import CoreMotion
import ImageIO
import Metal
import MetalPerformanceShaders
import SwiftUI

final class CameraPreviewView: UIView, SampleBufferProvider {
    // weak var delegate: CameraPreviewDelegate? // Removed unused delegate

    private var compositionOverlayView: GuidelinesOverlayView?
    private var hdrModeEnabled: Bool = false
    private let deviceManager = CameraDeviceManager.shared
    private let orientationManager: OrientationManager
    // exposure manager
    private var focusManager: FocusManager?
    private var exposureManager: ExposureManager?
    // filterrelatedproperties
    private let previewRenderController: PreviewRenderController
    private var filterPreviewLayer: CAMetalLayer?
    private var filterManager: FilterManager = .shared

    /// AI photo mode
    private var automationManager: CameraAutomationManager?

    /// audiomanager
    private var audioManager: AudioManager?

    weak var viewState: CameraViewState?

    /// camerasetstate
    private weak var settingsState: CameraSettingsState?

    /// session manager
    private weak var sessionManager: CameraSessionManager?

    /// SampleBuffer controller(datarecording)
    private let sampleBufferController: SampleBufferController

    var latestSampleBuffer: CMSampleBuffer?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - haptic feedback generators()

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    var aspectRatio: Double = 3.0 / 4.0 {
        didSet {
            if oldValue != aspectRatio {
                setNeedsLayout()
            }
        }
    }

    /// : gestureprocessor
    private var gestureHandler: CameraGestureHandler?

    /// zoom gesture handler
    private var zoomGestureHandler: ZoomGestureHandler?

    // Joystick Zoom State
    private var zoomTimer: Timer?
    private var currentZoomPanDelta: CGFloat = 0
    private var joystickView: JoystickOverlayView?

    // center-area exposure compensation adjustment state
    private var initialExposureCompensation: Float = 0
    private var cumulativeExposureDelta: Float = 0
    private var lastExposureFeedbackStep: Int?

    /// left-side filter intensity adjustment state
    private var lastFilterIntensityFeedbackStep: Int?

    // MARK: - camerainitialization

    init(
        sessionManager: CameraSessionManager,
        orientationManager: OrientationManager,
        settingsState: CameraSettingsState,
        previewRenderController: PreviewRenderController,
        sampleBufferController: SampleBufferController
    ) {
        self.sessionManager = sessionManager
        self.orientationManager = orientationManager
        self.settingsState = settingsState
        self.previewRenderController = previewRenderController
        self.sampleBufferController = sampleBufferController
        super.init(frame: .zero)

        setupCamera()
        setupCompositionOverlay()
        setupGestureHandler()
        setupZoomGestureHandler()

        configurePreviewRendering()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError(
            "init(coder:) has not been implemented. Please use init()"
        )
    }

    deinit {
        print("🗑️ [CameraPreviewView] deinit called - Cleaning up resources")

        // clean upAIrelated, not viewWillDisappear
        automationManager = nil

        // stopin progressoperation
        stopCameraSession()

        // clean up sample buffer
        latestSampleBuffer = nil

        // clean up Metal
        filterPreviewLayer?.removeFromSuperlayer()
        filterPreviewLayer = nil

        // clean upmanager
        focusManager = nil
        exposureManager = nil

        // clean upgestureprocessor
        gestureHandler = nil
        zoomGestureHandler = nil

        // clean up
        cancellables.removeAll()

        print("✅ [CameraPreviewView] deinit complete")
    }

    // MARK: - device orientation observation

    // : orientationdeviceswitchobserve CameraSessionManager

    // MARK: - camera session lifecycle management

    /// start the camera session
    func startCameraSession() {
        print("📷 [CameraPreviewView] startCameraSession 开始启动相机会话")
        sessionManager?.startSession()

        // Ensure metal layer has a valid drawable size right after start
        DispatchQueue.main.async { [weak self] in
            guard let self, let metalLayer = self.filterPreviewLayer else {
                print("⚠️ [CameraPreviewView] metalLayer 为空，无法设置 drawable size")
                return
            }
            if metalLayer.drawableSize == .zero {
                print("📐 [CameraPreviewView] metalLayer drawableSize 为零，重新设置")
                self.setNeedsLayout()
                self.layoutIfNeeded()
            } else {
                print(
                    "✅ [CameraPreviewView] metalLayer drawableSize 正常: \(metalLayer.drawableSize)"
                )
            }
        }
    }

    /// stop the camera session
    func stopCameraSession() {
        sessionManager?.stopSession()
        audioManager?.reset()
    }

    /// setcamerasession
    private func setupCamera() {
        // set session(use session manager, and delegate)
        let captureMode = settingsState?.currentCaptureMode ?? .photo
        sessionManager?
            .setupSession(
                captureMode: captureMode,
                videoDelegate: sampleBufferController,
                audioDelegate: sampleBufferController
            )

        // setpreview(main thread)
        DispatchQueue.main.async { [weak self] in
            self?.setupPreviewLayer()
        }

        // observe App, ensure
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

        // configurebutton (iOS 18+)
        if #available(iOS 18.0, *) {
            CameraControlManager.shared.setupCaptureInteraction(for: self)
        }
    }

    @objc private func handleWillEnterForeground() {
        print("📱 [CameraPreviewView] App will enter foreground - forcing layout update")
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsLayout()
            self?.layoutIfNeeded()
        }
    }

    private func setupPreviewLayer() {
        setupFilterPreviewLayer()
        // ensuregrid linesviewMetal
        bringGridOverlayToFront()
    }

    private func setupFilterPreviewLayer() {
        print("🔧 [CameraPreviewView] setupFilterPreviewLayer 开始")
        guard filterPreviewLayer == nil else {
            print("⚠️ [CameraPreviewView] filterPreviewLayer 已存在，跳过创建")
            return
        }

        print("🎨 [CameraPreviewView] 创建 CAMetalLayer")
        let metalLayer = CAMetalLayer()
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ [CameraPreviewView] 无法创建 Metal 设备")
            return
        }
        metalLayer.device = device
        print("✅ [CameraPreviewView] Metal 设备创建成功: \(device.name)")

        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.frame = bounds
        metalLayer.contentsGravity = .resizeAspectFill

        // configure
        if #available(iOS 11.0, *) {
            metalLayer.maximumDrawableCount = 3 // maximumdrawable
        }
        metalLayer.presentsWithTransaction = false // sync

        print("📐 [CameraPreviewView] Metal Layer frame: \(metalLayer.frame)")
        layer.addSublayer(metalLayer)
        filterPreviewLayer = metalLayer
        previewRenderController.attach(to: metalLayer)
        print("✅ [CameraPreviewView] setupFilterPreviewLayer 完成")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // logic: let Metal Layer view
        // view SwiftUI system(.aspectRatio modifier)
        // this waycan ensure Metal Layer viewsync
        if let metalLayer = filterPreviewLayer {
            // use CATransaction, ensure layer frame update view bounds
            if metalLayer.frame != bounds {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                metalLayer.frame = bounds
                CATransaction.commit()
            }

            // update drawable (use scale, ensure)
            let scale = UIScreen.main.scale
            if metalLayer.contentsScale != scale {
                metalLayer.contentsScale = scale
            }

            let drawableSize = CGSize(width: bounds.width * scale,
                                      height: bounds.height * scale)

            if metalLayer.drawableSize != drawableSize {
                metalLayer.drawableSize = drawableSize
                previewRenderController.attach(to: metalLayer)
            }
        }

        // update/exposure managerpreview
        focusManager?.setPreviewFrame(bounds)
        exposureManager?.setPreviewFrame(bounds)
    }

    // MARK: - Camera Operations

    func updateGuidelines(
        _ guideType: CameraSettingsState.GuidelinesType
    ) {
        compositionOverlayView?.type = guideType
        compositionOverlayView?.isHidden = (guideType == .off)
        // guidelines, ensure
        if guideType != .off {
            bringGridOverlayToFront()
        }
    }

    func updateHDRMode(_ enabled: Bool) {
        hdrModeEnabled = enabled
    }

    private func setupCompositionOverlay() {
        let guidelinesView = GuidelinesOverlayView()
        guidelinesView.translatesAutoresizingMaskIntoConstraints = false
        guidelinesView.isUserInteractionEnabled = false
        addSubview(guidelinesView)

        NSLayoutConstraint.activate([
            guidelinesView.topAnchor.constraint(equalTo: topAnchor),
            guidelinesView.leadingAnchor.constraint(equalTo: leadingAnchor),
            guidelinesView.trailingAnchor.constraint(equalTo: trailingAnchor),
            guidelinesView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        compositionOverlayView = guidelinesView
    }

    private func bringGridOverlayToFront() {
        if let gridView = compositionOverlayView {
            bringSubviewToFront(gridView)
        }
    }

    // MARK: - gesture recognition setup

    private func setupGestureHandler() {
        gestureHandler = CameraGestureHandler(
            view: self,
            delegate: self,
            orientationManager: orientationManager
        )
    }

    private func setupZoomGestureHandler() {
        zoomGestureHandler = ZoomGestureHandler()
    }

    private func configurePreviewRendering() {
        if let layer = filterPreviewLayer {
            previewRenderController.attach(to: layer)
        }

        previewRenderController.frameSubject
            .sink { [weak self] buffer in
                guard let self else { return }
                if self.automationManager != nil {
                    self.latestSampleBuffer = buffer
                }
            }
            .store(in: &cancellables)

        previewRenderController.onRenderDurationMeasured = { duration in
            if duration > 1.0 / 30.0 {
                print("⚠️ [PreviewRenderController] 渲染耗时: \(duration * 1000) ms")
            }
        }
    }

    func setupFocusManagerIfNeeded(_ focusManager: FocusManager) {
        guard self.focusManager !== focusManager else { return }
        self.focusManager = focusManager
        focusManager.setCurrentCamera(CameraDeviceManager.shared.getCurrentCamera())
        focusManager.setPreviewSize(bounds.size)

        if focusManager.isFocusSupported(), focusManager.getSupportedFocusModes().contains(.continuous) {
            focusManager.enableContinuousAutoFocus()
        }
    }

    func setupExposureManagerIfNeeded(_ exposureManager: ExposureManager) {
        guard self.exposureManager !== exposureManager else { return }
        self.exposureManager = exposureManager
        exposureManager.setCurrentCamera(CameraDeviceManager.shared.getCurrentCamera())
        exposureManager.setPreviewSize(bounds.size)
    }

    // MARK: - AI photo mode

    func setupAutomationManagerIfNeeded(_ automationManager: CameraAutomationManager) {
        guard self.automationManager !== automationManager else { return }
        self.automationManager = automationManager
    }

    func setupAudioManagerIfNeeded(_ audioManager: AudioManager) {
        guard self.audioManager !== audioManager else { return }
        self.audioManager = audioManager
    }

    // MARK: - lifecycle management

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // CameraPreviewView not then AI state, statemanagementupper-layer CameraView
    }

    // MARK: - SampleBufferProvider

    func getCurrentSampleBuffer() -> CMSampleBuffer? {
        latestSampleBuffer
    }

    // MARK: - helper methods

    private func triggerImpactFeedback() {
        impactFeedback.impactOccurred()
    }

    private func triggerSelectionFeedback() {
        selectionFeedback.selectionChanged()
    }

    private func showInfo(_ message: String, icon: String) {
        Task { @MainActor in
            viewState?.showInfo(message, customIcon: icon)
        }
    }
}

// MARK: - CameraGestureHandlerDelegate

extension CameraPreviewView: CameraGestureHandlerDelegate {
    func didPinch(scale: CGFloat, state: UIGestureRecognizer.State) {
        // ZoomGestureHandler
        zoomGestureHandler?.handlePinchGesture(scale: scale, state: state)
    }

    func didTap(at point: CGPoint) {
        guard let focusManager else { return }
        if focusManager.isFocusLocked {
            focusManager.unlockFocus()
            showInfo(.cameraFocusUnlocked.localized, icon: "lock.open.fill")
        } else if focusManager.isFocusSupported() {
            focusManager.focus(at: point)
        }
    }

    func didLongPress(at point: CGPoint, state: UIGestureRecognizer.State) {
        guard state == .began, let focusManager else { return }
        focusManager.lockFocus(at: point)
        triggerImpactFeedback()
        showInfo(.cameraFocusLocked.localized, icon: "lock.fill")
    }

    func didPanVerticallyOnLeftSide(delta: CGFloat, state: UIGestureRecognizer.State) {
        let currentFilter = filterManager.selectedFilter
        let step = FilterIntensityConstants.intensityStep
        let minIntensity = FilterIntensityConstants.minIntensity
        var intensity = filterManager.getIntensity(for: currentFilter)

        switch state {
        case .began:
            lastFilterIntensityFeedbackStep = Int(floor(intensity / step))
            triggerImpactFeedback()

        case .changed:
            intensity = (intensity + Float(-delta / 200.0)).clamped(to: minIntensity ... 1.0)
            filterManager.setIntensity(intensity, for: currentFilter)

            let currentStep = Int(floor(intensity / step))
            if currentStep != lastFilterIntensityFeedbackStep {
                triggerSelectionFeedback()
                lastFilterIntensityFeedbackStep = currentStep
                showFilterIntensityInfo(currentFilter, intensity: intensity)
            }

        case .ended, .cancelled:
            triggerImpactFeedback()
            lastFilterIntensityFeedbackStep = nil
            showFilterIntensityInfo(currentFilter, intensity: intensity)

        default:
            break
        }
    }

    private func showFilterIntensityInfo(_ filter: FilterIdentifier, intensity: Float) {
        let toastContent = filterManager.makeFilterSwitchToastContent(for: filter, intensity: intensity)
        showInfo(toastContent.message, icon: toastContent.icon)
    }

    func didPanVerticallyInCenter(delta: CGFloat, state: UIGestureRecognizer.State) {
        guard let exposureManager, exposureManager.canAdjustExposure else { return }
        let range = exposureManager.getExposureCompensationRange()
        guard range.max > range.min else { return }
        let step: Float = 0.1

        switch state {
        case .began:
            initialExposureCompensation = exposureManager.exposureCompensation.clamped(to: range.min ... range.max)
            cumulativeExposureDelta = 0
            lastExposureFeedbackStep = Int(floor(initialExposureCompensation / step))
            triggerImpactFeedback()

        case .changed:
            cumulativeExposureDelta += Float(-delta / 200.0)
            let newCompensation = (initialExposureCompensation + cumulativeExposureDelta).clamped(to: range.min ... range.max)
            exposureManager.exposureCompensation = newCompensation

            let currentStep = Int(floor(newCompensation / step))
            if currentStep != lastExposureFeedbackStep {
                triggerSelectionFeedback()
                lastExposureFeedbackStep = currentStep
                showExposureInfo(newCompensation)
            }

        case .ended, .cancelled:
            triggerImpactFeedback()
            lastExposureFeedbackStep = nil
            showExposureInfo(exposureManager.exposureCompensation)

        default:
            break
        }
    }

    private func showExposureInfo(_ ev: Float) {
        showInfo(.cameraExposureValueFormat.localized(ev), icon: "plus.forwardslash.minus")
    }

    func didPanVerticallyOnRightSide(delta: CGFloat, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            currentZoomPanDelta = delta
            setupJoystickView()
            updateJoystickView(delta: delta)
            startZoomTimer()
            triggerImpactFeedback()

        case .changed:
            currentZoomPanDelta += delta
            updateJoystickView(delta: currentZoomPanDelta)

        case .ended, .cancelled:
            stopZoomTimer()
            removeJoystickView()
            triggerImpactFeedback()

        default:
            break
        }
    }

    private func startZoomTimer() {
        zoomTimer?.invalidate()
        zoomTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.handleZoomTimer()
        }
    }

    private func stopZoomTimer() {
        zoomTimer?.invalidate()
        zoomTimer = nil
        currentZoomPanDelta = 0
    }

    private func handleZoomTimer() {
        let sensitivity = 0.0001
        let rate = -Double(currentZoomPanDelta) * sensitivity
        let newZoom = deviceManager.zoomManager.deviceZoomFactor * (1.0 + rate)
        deviceManager.zoomManager.setZoomFactor(newZoom)
    }

    // MARK: - Joystick UI

    private func setupJoystickView() {
        guard joystickView == nil else { return }

        let joystick = JoystickOverlayView()
        joystick.translatesAutoresizingMaskIntoConstraints = false
        addSubview(joystick)
        // Ensure joystick is on top of everything (grid, filters, etc)
        bringSubviewToFront(joystick)
        joystickView = joystick

        NSLayoutConstraint.activate([
            joystick.centerYAnchor.constraint(equalTo: centerYAnchor),
            joystick.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32), // Increased margin to avoid edge overlap
            joystick.widthAnchor.constraint(equalToConstant: 40),
            joystick.heightAnchor.constraint(equalToConstant: 240), // Taller track
        ])

        joystick.alpha = 0
        UIView.animate(withDuration: 0.2) {
            joystick.alpha = 1
        }
    }

    private func updateJoystickView(delta: CGFloat) {
        let maxDrag: CGFloat = 300
        let maxKnobOffset: CGFloat = 80
        let progress = (delta / maxDrag).clamped(to: -1.0 ... 1.0)
        joystickView?.updateKnobOffset(progress * maxKnobOffset)
    }

    private func removeJoystickView() {
        guard let joystick = joystickView else { return }
        UIView.animate(withDuration: 0.2, animations: {
            joystick.alpha = 0
        }) { _ in
            joystick.removeFromSuperview()
            self.joystickView = nil
        }
    }

    func didSwipeLeft() {
        switchFilter(next: true)
    }

    func didSwipeRight() {
        switchFilter(next: false)
    }

    func didSwipeUp() {}
    func didSwipeDown() {}

    private func switchFilter(next: Bool) {
        _ = next ? filterManager.selectNextFilter() : filterManager.selectPreviousFilter()
        triggerImpactFeedback()
    }
}

extension CGRect {
    var isFinite: Bool {
        !origin.x.isNaN && !origin.y.isNaN && !size.width.isNaN && !size.height.isNaN &&
            origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite &&
            size.width > 0 && size.height > 0
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
