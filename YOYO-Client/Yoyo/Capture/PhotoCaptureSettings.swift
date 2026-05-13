import AVFoundation
import Foundation
import UIKit

/*
 * PhotoCaptureSettings - photo capture settings builder
 *
 * features:
 * 1. AVCapturePhotoSettings createconfigurelogic
 * 2. supportcaptureformat: JPEG, HEIC, RAW, ProRAW
 * 3. Live Photo, flash, HDR
 * 4. autoformatdowngrade(RAW zoomdowngrade HEIC)
 * 5. setinterface
 */

/// photo capture settings builder
final class PhotoCaptureSettings {
    static let shared = PhotoCaptureSettings(
        sessionManager: .shared,
        orientationManager: .shared,
        photoOutput: nil
    )

    // MARK: - dependencies

    private weak var sessionManager: CameraSessionManager?
    private weak var orientationManager: OrientationManager?
    private weak var photoOutput: AVCapturePhotoOutput?
    /// ensureget photoOutput reference
    private func getPhotoOutput() -> AVCapturePhotoOutput? {
        if let output = photoOutput {
            return output
        }

        // ifcurrentreference, sessionManager get
        if let sessionManager {
            let newOutput = sessionManager.getStillImageOutput()
            if let newOutput {
                photoOutput = newOutput
                print("🔍 [PhotoCaptureSettings] Retrieved photoOutput from sessionManager: \(newOutput)")
            }
            return newOutput
        }

        print("⚠️ [PhotoCaptureSettings] Unable to get photoOutput reference")
        return nil
    }

    // MARK: - capture options

    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var livePhotoEnabled: Bool = false
    private var livePhotoMovieURL: URL?

    // MARK: - initialization

    private init(
        sessionManager: CameraSessionManager,
        orientationManager: OrientationManager,
        photoOutput: AVCapturePhotoOutput?
    ) {
        self.sessionManager = sessionManager
        self.orientationManager = orientationManager
        self.photoOutput = photoOutput
    }

    // MARK: - public configuration methods

    /// updateflashstate
    func updateFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
    }

    /// update Live Photo state
    func updateLivePhoto(_ enabled: Bool) async {
        print("🔍 [updateLivePhoto] Setting LivePhoto enabled: \(enabled)")
        livePhotoEnabled = enabled
        var outputRef = getPhotoOutput()

        print("🔍 [updateLivePhoto] outputRef: \(outputRef != nil ? "exists" : "nil")")
        if let output = outputRef {
            print("🔍 [updateLivePhoto] isLivePhotoCaptureSupported: \(output.isLivePhotoCaptureSupported)")
            print("🔍 [updateLivePhoto] current isLivePhotoCaptureEnabled: \(output.isLivePhotoCaptureEnabled)")
            print("🔍 [updateLivePhoto] sessionPreset: \(String(describing: sessionManager?.captureSession?.sessionPreset.rawValue ?? "unknown"))")
            if let camera = CameraDeviceManager.shared.getCurrentCamera() {
                print("🔍 [updateLivePhoto] camera activeFormat: \(String(describing: camera.activeFormat))")
                print("🔍 [updateLivePhoto] camera deviceType: \(camera.deviceType.rawValue)")
            }
        }

        guard let output = outputRef, output.isLivePhotoCaptureSupported else {
            print("🔍 [updateLivePhoto] Cannot enable LivePhoto - not supported")
            return
        }

        if let sessionManager {
            await sessionManager.configureLivePhoto(enabled)
            print("🔍 [updateLivePhoto] Set isLivePhotoCaptureEnabled = \(enabled) via sessionManager")
        } else {
            output.isLivePhotoCaptureEnabled = enabled
            print("🔍 [updateLivePhoto] Set isLivePhotoCaptureEnabled = \(enabled) directly")
        }

        print("🔍 [updateLivePhoto] Final isLivePhotoCaptureEnabled: \(output.isLivePhotoCaptureEnabled)")
    }

    /// photocaptureset
    /// - Parameter format: captureformat
    /// - Returns: configure AVCapturePhotoSettings useformat
    func buildPhotoSettings(
        quality: CameraSettingsState.CaptureQuality,
        format: CameraSettingsState.ImageFileFormat
    ) -> (
        AVCapturePhotoSettings,
        CameraSettingsState.CaptureQuality
    ) {
        // 1. createset
        var (photoSettings, actualQuality) = createPhotoSettings(
            quality: quality,
            format: format
        )

        // 2. configure Live Photo
        (photoSettings, actualQuality) = configureLivePhoto(
            photoSettings: photoSettings,
            actualQuality: actualQuality,
            format: format
        )

        // 3. configureflash
        configureFlash(photoSettings: photoSettings)

        // 4. configurequalitystabilization
        configureQualityAndStabilization(
            photoSettings: photoSettings,
            actualQuality: actualQuality
        )

        // 5. configurehigh resolution
        configureHighResolution(photoSettings: photoSettings)

        // 6. configureorientation
        configureOrientation(photoSettings: photoSettings)

        return (photoSettings, actualQuality)
    }

    // MARK: - private configuration methods

    /// createphotoset, formatdowngrade
    private func createPhotoSettings(
        quality: CameraSettingsState.CaptureQuality,
        format: CameraSettingsState.ImageFileFormat
    ) -> (
        AVCapturePhotoSettings,
        CameraSettingsState.CaptureQuality
    ) {
        var actualQuality = quality
        let photoSettings: AVCapturePhotoSettings

        switch quality {
        case .proRaw:
            // checkwhethersupport ProRAW, and ProRAW format
            if let output = getPhotoOutput(),
               output.isAppleProRAWSupported,
               let proRawFormat = output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) })
            {
                print("📸 [PhotoCaptureSettings] ProRAW requested, using format: \(proRawFormat)")
                photoSettings = AVCapturePhotoSettings(
                    rawPixelFormatType: proRawFormat
                )
                actualQuality = .proRaw
            } else {
                print("⚠️ [PhotoCaptureSettings] ProRAW requested but not supported/found. Fallback to Standard")
                // ProRAW not supportdowngrade Standard
                let pair = makeStandardPhotoSettings(format: format)
                photoSettings = pair.0
                actualQuality = .standard
            }

        case .standard:
            let pair = makeStandardPhotoSettings(format: format)
            photoSettings = pair.0
            actualQuality = .standard
        }

        return (photoSettings, actualQuality)
    }

    /// createphotoset(RAW)
    private func makeStandardPhotoSettings(
        format: CameraSettingsState.ImageFileFormat
    ) -> (
        AVCapturePhotoSettings,
        CameraSettingsState.CaptureQuality
    ) {
        if format == .heic {
            let settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
            return (settings, .standard)
        }

        return (AVCapturePhotoSettings(), .standard)
    }

    /// configure Live Photo
    private func configureLivePhoto(
        photoSettings: AVCapturePhotoSettings,
        actualQuality: CameraSettingsState.CaptureQuality,
        format: CameraSettingsState.ImageFileFormat
    ) -> (
        AVCapturePhotoSettings,
        CameraSettingsState.CaptureQuality
    ) {
        print("🔍 [configureLivePhoto] Starting configuration...")
        print("🔍 [configureLivePhoto] livePhotoEnabled: \(livePhotoEnabled)")
        print("🔍 [configureLivePhoto] actualQuality: \(actualQuality)")
        print("🔍 [configureLivePhoto] isRaw: \(actualQuality.isRaw)")

        // ifnot yet Live Photo,
        guard livePhotoEnabled else {
            print("🔍 [configureLivePhoto] Skipping LivePhoto - livePhotoEnabled: false")
            livePhotoMovieURL = nil
            // Ensure the returned `photoSettings` does not set `livePhotoMovieFileURL`
            // Avoid the error "livePhotoMovieFileURL must be nil if self.livePhotoCaptureEnabled is NO"
            photoSettings.livePhotoMovieFileURL = nil
            return (photoSettings, actualQuality)
        }

        // : actualQuality RAW, if Live Photo, configure
        // logiccreateformat Settings (because Live Photo not support RAW), implementautodowngrade
        if actualQuality.isRaw {
            print("🔍 [configureLivePhoto] LivePhoto enabled with RAW quality - will attempt to downgrade to Standard")
        }

        var outputRef = getPhotoOutput()

        print("🔍 [configureLivePhoto] outputRef: \(outputRef != nil ? "exists" : "nil")")
        if let output = outputRef {
            print("🔍 [configureLivePhoto] isLivePhotoCaptureSupported: \(output.isLivePhotoCaptureSupported)")
            print("🔍 [configureLivePhoto] isLivePhotoCaptureEnabled: \(output.isLivePhotoCaptureEnabled)")
            print("🔍 [configureLivePhoto] sessionPreset: \(String(describing: sessionManager?.captureSession?.sessionPreset.rawValue ?? "unknown"))")
            if let camera = CameraDeviceManager.shared.getCurrentCamera() {
                print("🔍 [configureLivePhoto] camera activeFormat: \(String(describing: camera.activeFormat))")
                print("🔍 [configureLivePhoto] camera deviceType: \(camera.deviceType.rawValue)")
            }
        }

        guard let output = outputRef, output.isLivePhotoCaptureSupported else {
            print("🔍 [configureLivePhoto] LivePhoto not supported - output: \(outputRef != nil), isSupported: \(outputRef?.isLivePhotoCaptureSupported ?? false)")
            livePhotoMovieURL = nil
            return (photoSettings, actualQuality)
        }

        print("🔍 [configureLivePhoto] LivePhoto is supported, configuring...")

        let livePhotoMovieFileURL = createTempLivePhotoMovieURL()
        print("[LivePhoto] livePhotoMovieFileURL: \(livePhotoMovieFileURL.path)")

        let pair = makeStandardPhotoSettings(format: format)
        let newPhotoSettings = pair.0
        newPhotoSettings.livePhotoMovieFileURL = livePhotoMovieFileURL
        livePhotoMovieURL = livePhotoMovieFileURL

        if #available(iOS 11.0, *) {
            newPhotoSettings.livePhotoVideoCodecType = AVVideoCodecType.h264
            print("🔍 [configureLivePhoto] Set livePhotoVideoCodecType to h264")
        }

        print("🔍 [configureLivePhoto] Configuration complete - URL: \(livePhotoMovieFileURL.path)")

        return (newPhotoSettings, pair.1)
    }

    /// configureflash
    private func configureFlash(photoSettings: AVCapturePhotoSettings) {
        guard let camera = CameraDeviceManager.shared.getCurrentCamera(),
              camera.hasFlash
        else {
            return
        }
        photoSettings.flashMode = flashMode
    }

    /// configurequalitystabilization
    private func configureQualityAndStabilization(
        photoSettings: AVCapturePhotoSettings,
        actualQuality: CameraSettingsState.CaptureQuality
    ) {
        if #available(iOS 13.0, *), !actualQuality.isRaw {
            configureQualityPrioritization(photoSettings: photoSettings)
        } else if actualQuality.isRaw {
            print(
                "[PhotoCaptureSettings] RAW format does not support quality prioritization"
            )
        } else {
            configureStabilization(photoSettings: photoSettings)
        }
    }

    /// configurequality(iOS 13+)
    private func configureQualityPrioritization(
        photoSettings: AVCapturePhotoSettings
    ) {
        guard let output = getPhotoOutput() else { return }

        let desiredQuality: AVCapturePhotoOutput.QualityPrioritization = .quality

        if desiredQuality.rawValue <= output.maxPhotoQualityPrioritization.rawValue {
            photoSettings.photoQualityPrioritization = desiredQuality
        } else {
            photoSettings.photoQualityPrioritization = output.maxPhotoQualityPrioritization
        }
    }

    /// configurestabilization(iOS 13)
    private func configureStabilization(photoSettings: AVCapturePhotoSettings) {
        if #available(iOS 13.0, *) {
            return
        } else {
            guard let output = getPhotoOutput(),
                  output.isStillImageStabilizationSupported else { return }
            photoSettings.isAutoStillImageStabilizationEnabled = true
        }
    }

    /// configurehigh resolution
    private func configureHighResolution(photoSettings: AVCapturePhotoSettings) {
        guard let output = getPhotoOutput() else { return }

        if #available(iOS 16.0, *) {
            let maxDimensions = output.maxPhotoDimensions
            guard maxDimensions.width > 0, maxDimensions.height > 0 else { return }
            photoSettings.maxPhotoDimensions = maxDimensions
        } else if output.isHighResolutionCaptureEnabled {
            photoSettings.isHighResolutionPhotoEnabled = true
        }
    }

    /// configurephotoorientation
    private func configureOrientation(photoSettings _: AVCapturePhotoSettings) {
        guard let output = getPhotoOutput(),
              let connection = output.connection(with: .video),
              let orientationManager else { return }

        let videoOrientation = orientationManager.currentAVCaptureVideoOrientation
        let isFrontCamera = CameraDeviceManager.shared.getCurrentCamera()?.position == .front

        connection.videoOrientation = videoOrientation
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isFrontCamera
    }

    /// createtemporary Live Photo video URL
    private func createTempLivePhotoMovieURL() -> URL {
        FileManager.createTempLivePhotoVideoURL(prefix: "IMG")
    }

    /// get Live Photo video URL(ifconfigure)
    func getLivePhotoMovieURL() -> URL? {
        livePhotoMovieURL
    }

    /// Live Photo video URL
    func clearLivePhotoMovieURL() {
        livePhotoMovieURL = nil
    }
}
