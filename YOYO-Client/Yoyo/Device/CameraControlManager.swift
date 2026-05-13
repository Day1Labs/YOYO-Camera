import AVFoundation
import AVKit
import Combine
import UIKit

/// cameramanager (support iOS 18+ iPhone 16/17 Camera Control take a photo)
/// responsibilities: management AVCaptureControl andmanager(Zoom, Exposure)
@available(iOS 18.0, *)
final class CameraControlManager: NSObject, AVCaptureSessionControlsDelegate {
    // MARK: - Singleton

    static let shared = CameraControlManager()

    // MARK: - Private Properties

    /// operationqueue
    private let controlQueue = DispatchQueue(label: "com.day1-labs.yoyo.camera.control", qos: .userInitiated)

    /// Combine management
    private var zoomSubscription: AnyCancellable?
    private var exposureSubscription: AnyCancellable?

    /// currentconfigure Session(referencereference)
    private weak var currentSession: AVCaptureSession?

    /// session operation queuereference
    private var sessionQueue: DispatchQueue?

    /// currentreference
    private var zoomSlider: AVCaptureSlider?
    private var exposureSlider: AVCaptureSlider?

    /// Shutter interaction object
    private var captureInteraction: AVCaptureEventInteraction?

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    deinit {
        cleanup()
    }

    // MARK: - AVCaptureSessionControlsDelegate

    func sessionControlsDidBecomeActive(_: AVCaptureSession) {
        print("📸 [CameraControlManager] 硬件控制已激活")
    }

    func sessionControlsWillEnterFullscreenAppearance(_: AVCaptureSession) {
        print("📸 [CameraControlManager] 硬件控制将进入全屏模式")
    }

    func sessionControlsWillExitFullscreenAppearance(_: AVCaptureSession) {
        print("📸 [CameraControlManager] 硬件控制将退出全屏模式")
    }

    func sessionControlsDidBecomeInactive(_: AVCaptureSession) {
        print("📸 [CameraControlManager] 硬件控制已停用")
    }

    // MARK: - Public Methods

    /// Capture Session configure
    /// - Parameters:
    ///   - session: current AVCaptureSession
    ///   - sessionQueue: Session operationqueue (AVCaptureControl Session Queue)
    ///   - forceUpdate: whetherupdate(for exampleswitchcameradevice)
    func setupControls(for session: AVCaptureSession, sessionQueue: DispatchQueue, forceUpdate: Bool = false) {
        // ensuresystemsupportfeatures
        guard session.supportsControls else {
            print("⚠️ [CameraControlManager] 设备不支持 Camera Control")
            return
        }

        // if session not update, configure
        if !forceUpdate, currentSession === session, !session.controls.isEmpty {
            print("⏭️ [CameraControlManager] Session 已配置，跳过")
            return
        }

        print("📸 [CameraControlManager] 配置硬件控制按钮 (iPhone 16 Camera Control)")

        // clean upreference
        cleanupSubscriptions()

        // save session and queue reference
        currentSession = session
        self.sessionQueue = sessionQueue

        // sessionQueue configure
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureControlsOnQueue(session: session, sessionQueue: sessionQueue)

            // ⚠️ key: set controlsDelegate
            session.setControlsDelegate(self, queue: sessionQueue)
        }
    }

    /// configurecamera (supporttake a photo)
    /// - Parameter view: view
    func setupCaptureInteraction(for view: UIView) {
        // remove
        if let oldInteraction = captureInteraction {
            view.removeInteraction(oldInteraction)
            captureInteraction = nil
        }

        // create
        let interaction = AVCaptureEventInteraction { (event: AVCaptureEvent) in
            // onlybuttontriggercapture
            if event.phase == .began {
                print("📸 [CameraControlManager] 硬件快门触发")
                Task { @MainActor in
                    CameraCaptureService.shared.triggerShutterAction()
                }
            }
        }

        view.addInteraction(interaction)
        captureInteraction = interaction
    }

    /// removecamera
    /// - Parameter view: need to removeview
    func removeCaptureInteraction(from view: UIView) {
        if let interaction = captureInteraction {
            view.removeInteraction(interaction)
            captureInteraction = nil
        }
    }

    /// clean up
    func cleanup() {
        cleanupSubscriptions()
        removeControlsFromSession()
        zoomSlider = nil
        exposureSlider = nil
        currentSession = nil
    }

    // MARK: - Private Methods

    /// sessionQueue configure
    private func configureControlsOnQueue(session: AVCaptureSession, sessionQueue: DispatchQueue) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // remove
        session.controls.forEach { session.removeControl($0) }

        // configurezoom
        configureZoomSlider(session: session, sessionQueue: sessionQueue)

        // configureexposure
        configureExposureSlider(session: session, sessionQueue: sessionQueue)
    }

    /// configurezoom
    private func configureZoomSlider(session: AVCaptureSession, sessionQueue _: DispatchQueue) {
        let zoomManager = ZoomManager.shared
        let zoomRange = zoomManager.zoomRange

        // validatezoomrange
        guard zoomRange.min < zoomRange.max else {
            print("⚠️ [CameraControlManager] 缩放范围无效 (\(zoomRange.min)...\(zoomRange.max))，跳过配置")
            return
        }

        // createzoom(usecurrentdevicezoomrange)
        let title = String.categoryZoom.localized
        let minZoom = Float(zoomRange.min)
        let maxZoom = Float(zoomRange.max)
        let slider = AVCaptureSlider(
            title,
            symbolName: "magnifyingglass",
            in: minZoom ... maxZoom
        )

        // set(ensurerange)
        let initialValue = Float(zoomManager.deviceZoomFactor)
        slider.value = max(minZoom, min(maxZoom, initialValue))

        // setoperationcallback
        slider.setActionQueue(controlQueue) { value in
            Task { @MainActor in
                ZoomManager.shared.setZoomFactor(Double(value))
            }
        }

        // add session
        guard session.canAddControl(slider) else {
            print("⚠️ [CameraControlManager] 无法添加缩放控制")
            return
        }

        session.addControl(slider)
        zoomSlider = slider

        // App zoom, sync
        // use dropFirst() (manualset), configure
        // ⚠️: AVCaptureSlider.value setActionQueue queueset
        zoomSubscription = zoomManager.$deviceZoomFactor
            .dropFirst()
            .removeDuplicates()
            .receive(on: controlQueue)
            .sink { [weak slider, minZoom, maxZoom] factor in
                guard let slider else { return }
                // ensurerange
                let clampedValue = max(minZoom, min(maxZoom, Float(factor)))
                slider.value = clampedValue
            }
    }

    /// configureexposure
    private func configureExposureSlider(session: AVCaptureSession, sessionQueue _: DispatchQueue) {
        let exposureManager = ExposureManager.shared
        let range = exposureManager.getExposureCompensationRange()

        // validateexposurerange
        guard range.min < range.max else {
            print("⚠️ [CameraControlManager] 曝光补偿范围无效 (\(range.min)...\(range.max))，跳过配置")
            return
        }

        // createexposure
        let title = String.categoryExposureAction.localized
        let minExposure = range.min
        let maxExposure = range.max
        let slider = AVCaptureSlider(
            title,
            symbolName: "sun.max",
            in: minExposure ... maxExposure
        )

        // set(ensurerange)
        let initialValue = exposureManager.exposureCompensation
        slider.value = max(minExposure, min(maxExposure, initialValue))

        // setoperationcallback
        slider.setActionQueue(controlQueue) { value in
            print("☀️ [CameraControlManager] 硬件曝光调节: \(value)EV")
            Task { @MainActor in
                ExposureManager.shared.adjustExposureCompensation(value)
            }
        }

        // add session
        guard session.canAddControl(slider) else {
            print("⚠️ [CameraControlManager] 无法添加曝光控制")
            return
        }

        session.addControl(slider)
        exposureSlider = slider

        // App exposure, sync
        // use dropFirst() (manualset), configure
        // ⚠️: AVCaptureSlider.value setActionQueue queueset
        exposureSubscription = exposureManager.$exposureCompensation
            .dropFirst()
            .removeDuplicates()
            .receive(on: controlQueue)
            .sink { [weak slider, minExposure, maxExposure] value in
                guard let slider else { return }
                // ensurerange
                let clampedValue = max(minExposure, min(maxExposure, value))
                slider.value = clampedValue
            }
    }

    /// clean up
    private func cleanupSubscriptions() {
        zoomSubscription?.cancel()
        zoomSubscription = nil
        exposureSubscription?.cancel()
        exposureSubscription = nil
    }

    /// session remove
    private func removeControlsFromSession() {
        guard let session = currentSession else { return }

        if let zoom = zoomSlider {
            session.removeControl(zoom)
        }
        if let exposure = exposureSlider {
            session.removeControl(exposure)
        }
    }
}
