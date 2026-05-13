import AVFoundation
import Foundation
import SwiftUI

// MARK: - Camera shooting mode enumeration
enum CameraCaptureMode: String, CaseIterable {
    case photo = "Photo"
    case livePhoto = "LivePhoto"
    case movie = "Movie"
}

// MARK: - Camera settings status manager
@MainActor
final class CameraSettingsState: ObservableObject {
    static let shared = CameraSettingsState()

    @Published var torchEnabled = false

    // MARK: - Persistence settings
    @AppStorage("flashModeRaw") var flashModeRaw = AVCaptureDevice.FlashMode.off.rawValue

    var flashMode: AVCaptureDevice.FlashMode {
        get { AVCaptureDevice.FlashMode(rawValue: flashModeRaw) ?? .off }
        set {
            flashModeRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    @AppStorage("automationEnabled") var automationEnabled = true {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("saveOriginalEnabled") var saveOriginalEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("currentCaptureMode") var captureModeRaw: String = CameraCaptureMode.photo.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("guidelinesType") private var guidelinesTypeRaw: String = GuidelinesType.off.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("histogramEnabled") var histogramEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("hdrEnabled") var hdrEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("saveGPSEnabled") var saveGPSEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("copyrightEnabled") var copyrightEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("copyrightText") var copyrightText = "" {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage(
        "volumeButtonCaptureEnabled"
    ) var volumeButtonCaptureEnabled = false { // Volume button camera switch
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage(
        "timerCaptureEnabled"
    ) var timerCaptureEnabled = false { // Countdown photo switch
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("timerCaptureSeconds") var timerCaptureSeconds = 5 { // Countdown seconds
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("aspectRatio") var aspectRatio: Double = 2.0 / 3.0 {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("previewLatestPhoto") var previewLatestPhoto: Bool = true {
        didSet {
            objectWillChange.send()
        }
    }

    // MARK: - Video settings
    @AppStorage("videoResolution") private var videoResolutionRaw: String = VideoResolution.hd1080.rawValue {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .videoResolutionDidChange, object: nil)
        }
    }

    @AppStorage("videoFrameRate") private var videoFrameRateRaw: String = VideoFrameRate.fps30.rawValue {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .videoFrameRateDidChange, object: nil)
        }
    }

    @AppStorage("videoSaveFormat") private var videoSaveFormatRaw: String = VideoSaveFormat.mov.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("stabilizationEnabled") var stabilizationEnabled = false {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .videoStabilizationDidChange, object: nil)
        }
    }

    // MARK: - Audio settings
    @AppStorage("audioNoiseReductionEnabled") var audioNoiseReductionEnabled = true {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .audioSettingsDidChange, object: nil)
        }
    }

    @AppStorage("audioPickupPattern") private var audioPickupPatternRaw: String = AudioPickupPattern.voice.rawValue {
        didSet {
            objectWillChange.send()
            NotificationCenter.default.post(name: .audioSettingsDidChange, object: nil)
        }
    }

    // MARK: - File naming format settings
    @AppStorage("fileNamingFormat") private var fileNamingFormatRaw: String = FileNamingFormat.standard.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("customFileNamingFormat") var customFileNamingFormat: String = "{timestamp}_{type}_{uuid}" {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("fileNamingPrefix") var fileNamingPrefix: String = "YOYO" {
        didSet {
            objectWillChange.send()
        }
    }

    // MARK: - Default settings related to device capabilities
    func initializeVideoSettingsWithDeviceCapabilities() {
        let deviceManager = CameraDeviceManager.shared
        // Only adjust on first startup or if current settings are not supported.
        let maxResolution = deviceManager.getMaxSupportedVideoResolution()
        let maxFrameRate = deviceManager.getMaxSupportedVideoFrameRate()

        // If the currently set resolution is not supported, set it to the highest supported resolution.
        if !deviceManager.isVideoResolutionSupported(videoResolution) {
            videoResolution = maxResolution
        }

        // If the currently set frame rate is not supported, set it to the highest supported frame rate.
        if !deviceManager.isVideoFrameRateSupported(videoFrameRate) {
            videoFrameRate = maxFrameRate
        }
    }

    // MARK: - Runtime state (non-persistent)
    @Published var isCaptureSessionActive = false // Whether the camera capture session is active (replaces the original isPhotoCaptureActive)
    // MARK: - Shooting mode (Published + AppStorage two-way synchronization)
    @Published var currentCaptureMode: CameraCaptureMode = .photo {
        didSet {
            captureModeRaw = currentCaptureMode.rawValue
        }
    }

    // MARK: - initialization
    private init() {
        // Load the initial value from AppStorage into the Published property.
        if let mode = CameraCaptureMode(rawValue: captureModeRaw) {
            _currentCaptureMode = Published(initialValue: mode)
        }
    }

    // MARK: - Automation settings
    /// Filter Control
    @AppStorage("AutomationSettings.autoSelectFilter")
    var autoSelectFilter: Bool = true

    /// Focus Control
    @AppStorage("AutomationSettings.autoAdjustFocus")
    var autoAdjustFocus: Bool = true

    /// Exposure Control
    @AppStorage("AutomationSettings.autoAdjustExposure")
    var autoAdjustExposure: Bool = true

    @AppStorage("AutomationSettings.maxExposureBias")
    var maxExposureBias: Double = 10.0

    /// Manual Exposure Control (ISO & Shutter Speed)
    @AppStorage("AutomationSettings.autoAdjustISO")
    var autoAdjustISO: Bool = true

    @AppStorage("AutomationSettings.isoPreset")
    private var isoPresetRaw: String = ISOPreset.balanced.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    @AppStorage("AutomationSettings.autoAdjustShutterSpeed")
    var autoAdjustShutterSpeed: Bool = true

    @AppStorage("AutomationSettings.shutterSpeedPreset")
    private var shutterSpeedPresetRaw: String = ShutterSpeedPreset.handheld.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    /// White Balance Control
    @AppStorage("AutomationSettings.autoAdjustWhiteBalance")
    var autoAdjustWhiteBalance: Bool = true

    // MARK: - Composition guide line type
    enum GuidelinesType: String, CaseIterable {
        case off // Turn off auxiliary lines
        case ruleOfThirds // Rule of thirds
        case ruleOfThirdsWithDiagonal // 3x3 + diagonal
        case goldenRatio // Golden ratio
        case grid6x4 // 6x4 grid

        var systemIcon: String {
            switch self {
            case .off: return "nosign"
            case .ruleOfThirds: return "rectangle.split.3x3"
            case .ruleOfThirdsWithDiagonal: return "grid.circle"
            case .goldenRatio: return "rectangle.split.3x1"
            case .grid6x4: return "grid"
            }
        }
    }

    // MARK: - ISO/Shutter presets
    enum ISOPreset: String, CaseIterable {
        case lowNoise // Low noise priority (ISO <= 800)
        case balanced // Balanced (ISO <= 1600)
        case highISO // High ISO (ISO <= 3200)
        case extreme // Limit (ISO <= 6400)

        var displayName: String {
            switch self {
            case .lowNoise: return String.isoPresetLowNoise.localized
            case .balanced: return String.isoPresetBalanced.localized
            case .highISO: return String.isoPresetHigh.localized
            case .extreme: return String.isoPresetExtreme.localized
            }
        }

        var description: String {
            switch self {
            case .lowNoise: return String.isoPresetLowNoiseDesc.localized
            case .balanced: return String.isoPresetBalancedDesc.localized
            case .highISO: return String.isoPresetHighDesc.localized
            case .extreme: return String.isoPresetExtremeDesc.localized
            }
        }

        var maxISO: Double {
            switch self {
            case .lowNoise: return 800.0
            case .balanced: return 1600.0
            case .highISO: return 3200.0
            case .extreme: return 6400.0
            }
        }
    }

    enum ShutterSpeedPreset: String, CaseIterable {
        case handheld // Handheld shooting (>= 1/60s)
        case stable // Stable support (>= 1/30s)
        case tripod // Tripod (>= 1/15s)
        case longExposure // Long exposure (>= 1/4s)

        var displayName: String {
            switch self {
            case .handheld: return String.shutterPresetHandheld.localized
            case .stable: return String.shutterPresetStable.localized
            case .tripod: return String.shutterPresetTripod.localized
            case .longExposure: return String.shutterPresetLongExposure.localized
            }
        }

        var description: String {
            switch self {
            case .handheld: return String.shutterPresetHandheldDesc.localized
            case .stable: return String.shutterPresetStableDesc.localized
            case .tripod: return String.shutterPresetTripodDesc.localized
            case .longExposure: return String.shutterPresetLongExposureDesc.localized
            }
        }

        var minShutterSpeed: Double {
            switch self {
            case .handheld: return 1.0 / 60.0
            case .stable: return 1.0 / 30.0
            case .tripod: return 1.0 / 15.0
            case .longExposure: return 1.0 / 4.0
            }
        }
    }

    // MARK: - Countdown options
    enum TimerSeconds: Int, CaseIterable {
        case five = 5
        case ten = 10
        case thirty = 30

        var displayName: String {
            switch self {
            case .five: return "5s"
            case .ten: return "10s"
            case .thirty: return "30s"
            }
        }
    }

    // MARK: - Aspect Ratio Preset
    enum AspectRatioPreset: Double, CaseIterable {
        case square = 1.0
        case portrait = 0.8 // 4:5
        case traditional = 0.75 // 3:4
        case photo = 0.6667 // 2:3
        case story = 0.5625 // 9:16

        var displayName: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "4:5"
            case .traditional: return "3:4"
            case .photo: return "2:3"
            case .story: return "9:16"
            }
        }
    }

    // MARK: - Shooting format options
    enum CaptureQuality: String, CaseIterable {
        case standard // Processed
        case proRaw // Apple ProRaw

        var isRaw: Bool {
            self == .proRaw
        }
    }

    enum ImageFileFormat: String, CaseIterable {
        case jpeg // Standard JPEG format
        case heic // HEIC format
    }

    // MARK: - Video resolution enumeration
    enum VideoResolution: String, CaseIterable {
        case hd720 = "720p" // 720p HD (1280x720)
        case hd1080 = "HD" // 1080p Full HD (1920x1080)
        case hd4k = "4K" // 4K UHD (3840x2160)

        var displayName: String {
            switch self {
            case .hd720: return "720p"
            case .hd1080: return "HD"
            case .hd4k: return "4K"
            }
        }

        var dimensions: CGSize {
            switch self {
            case .hd720: return CGSize(width: 1280, height: 720)
            case .hd1080: return CGSize(width: 1920, height: 1080)
            case .hd4k: return CGSize(width: 3840, height: 2160)
            }
        }

        var pixelCount: Int {
            Int(dimensions.width * dimensions.height)
        }
    }

    // MARK: - Video frame rate enumeration
    enum VideoFrameRate: String, CaseIterable {
        case fps24 = "24" // 24 fps
        case fps30 = "30" // 30 fps
        case fps60 = "60" // 60 fps
        case fps120 = "120" // 120 fps

        var displayName: String {
            switch self {
            case .fps24: return "24"
            case .fps30: return "30"
            case .fps60: return "60"
            case .fps120: return "120"
            }
        }

        var value: Double {
            switch self {
            case .fps24: return 24.0
            case .fps30: return 30.0
            case .fps60: return 60.0
            case .fps120: return 120.0
            }
        }
    }

    // MARK: - File naming format enum
    enum FileNamingFormat: String, CaseIterable {
        case standard // 20241029_143022
        case classic // YOYO_0001
        case daily // 20241029_0001
        case pro // Photo_20241029_143022
        case custom // Custom format

        var displayName: String {
            switch self {
            case .standard: return .fileNamingStandard.localized
            case .classic: return .fileNamingClassic.localized
            case .daily: return .fileNamingDaily.localized
            case .pro: return .fileNamingPro.localized
            case .custom: return .fileNamingCustom.localized
            }
        }

        var description: String {
            switch self {
            case .standard: return "20241029_143022"
            case .classic: return "Photo_0001"
            case .daily: return "20241029_0001"
            case .pro: return "Photo_20241029_143022"
            case .custom: return .fileNamingCustomDesc.localized
            }
        }

        var template: String {
            switch self {
            case .standard: return "{year}{month}{day}_{hour}{minute}{second}"
            case .classic: return "{type}_{index}"
            case .daily: return "{year}{month}{day}_{index}"
            case .pro: return "{type}_{year}{month}{day}_{hour}{minute}{second}"
            case .custom: return "" // Use custom format
            }
        }
    }

    // MARK: - Video save format enumeration
    enum VideoSaveFormat: String, CaseIterable {
        case mov // MOV format
        case mp4 // MP4 format

        var displayName: String {
            switch self {
            case .mov: return "MOV"
            case .mp4: return "MP4"
            }
        }

        var fileType: AVFileType {
            switch self {
            case .mov: return .mov
            case .mp4: return .mp4
            }
        }
    }

    // MARK: - Audio radio mode enumeration
    enum AudioPickupPattern: String, CaseIterable {
        case ambient // Environment (omnidirectional)
        case voice // Vocal (cardioid pointing)
        case voiceEnhanced // Vocal enhancement (subcardioid pattern)

        var displayName: String {
            switch self {
            case .ambient: return .audioPickupAmbient.localized
            case .voice: return .audioPickupVoice.localized
            case .voiceEnhanced: return .audioPickupVoiceEnhanced.localized
            }
        }

        var description: String {
            switch self {
            case .ambient: return .audioPickupAmbientDesc.localized
            case .voice: return .audioPickupVoiceDesc.localized
            case .voiceEnhanced: return .audioPickupVoiceEnhancedDesc.localized
            }
        }

        var polarPattern: AVAudioSession.PolarPattern {
            switch self {
            case .ambient: return .omnidirectional
            case .voice: return .cardioid
            case .voiceEnhanced: return .subcardioid
            }
        }

        var systemIcon: String {
            switch self {
            case .ambient: return "dot.radiowaves.left.and.right"
            case .voice: return "person.wave.2"
            case .voiceEnhanced: return "waveform.and.person.filled"
            }
        }
    }

    // MARK: - Computed properties
    /// Actual effective aspect ratio: video mode is fixed at 9:16, other modes use user settings.
    var effectiveAspectRatio: Double {
        if currentCaptureMode == .movie {
            return AspectRatioPreset.story.rawValue // 9:16
        }
        return aspectRatio
    }

    var currentAspectRatioPreset: AspectRatioPreset {
        AspectRatioPreset.allCases
            .first { abs($0.rawValue - aspectRatio) < 0.001 } ?? .photo
    }

    var currentTimerSeconds: TimerSeconds {
        get { TimerSeconds(rawValue: timerCaptureSeconds) ?? .five }
        set { timerCaptureSeconds = newValue.rawValue }
    }

    var captureQuality: CaptureQuality {
        // RAW capture is temporarily disabled until the related flow is stabilized.
        /*
         if FilterManager.shared.selectedFilter.isFilmSimulation {
             let output = CameraSessionManager.shared.getStillImageOutput()
             // Check ProRAW first.
             if CameraDeviceManager.shared.isProRawCaptureSupported(photoOutput: output) {
                 return .proRaw
             }
         }
         */
        .standard
    }

    var imageFileFormat: ImageFileFormat {
        // Default to HEIC and extend later if scenario-specific selection is needed.
        .heic
    }

    // MARK: - Video settings computed properties
    var videoResolution: VideoResolution {
        get { VideoResolution(rawValue: videoResolutionRaw) ?? .hd1080 }
        set { videoResolutionRaw = newValue.rawValue }
    }

    var videoFrameRate: VideoFrameRate {
        get { VideoFrameRate(rawValue: videoFrameRateRaw) ?? .fps30 }
        set { videoFrameRateRaw = newValue.rawValue }
    }

    var videoSaveFormat: VideoSaveFormat {
        get { VideoSaveFormat(rawValue: videoSaveFormatRaw) ?? .mov }
        set { videoSaveFormatRaw = newValue.rawValue }
    }

    // MARK: - Audio settings computed properties
    var audioPickupPattern: AudioPickupPattern {
        get { AudioPickupPattern(rawValue: audioPickupPatternRaw) ?? .voice }
        set { audioPickupPatternRaw = newValue.rawValue }
    }

    // MARK: - File naming format computed properties
    var fileNamingFormat: FileNamingFormat {
        get { FileNamingFormat(rawValue: fileNamingFormatRaw) ?? .standard }
        set { fileNamingFormatRaw = newValue.rawValue }
    }

    var effectiveFileNamingTemplate: String {
        switch fileNamingFormat {
        case .custom:
            return customFileNamingFormat.isEmpty ? FileNamingFormat.standard.template : customFileNamingFormat
        default:
            return fileNamingFormat.template
        }
    }

    var guidelinesType: GuidelinesType {
        get {
            GuidelinesType(rawValue: guidelinesTypeRaw) ?? .off
        }
        set {
            guidelinesTypeRaw = newValue.rawValue
        }
    }

    var isoPreset: ISOPreset {
        get { ISOPreset(rawValue: isoPresetRaw) ?? .balanced }
        set { isoPresetRaw = newValue.rawValue }
    }

    var shutterSpeedPreset: ShutterSpeedPreset {
        get { ShutterSpeedPreset(rawValue: shutterSpeedPresetRaw) ?? .handheld }
        set { shutterSpeedPresetRaw = newValue.rawValue }
    }

    /// Convenient accessor.
    var maxISO: Double {
        isoPreset.maxISO
    }

    var minShutterSpeed: Double {
        shutterSpeedPreset.minShutterSpeed
    }

    // MARK: - method
    func setCaptureMode(_ mode: CameraCaptureMode) {
        currentCaptureMode = mode
        generateHapticFeedback()
    }

    func setAspectRatio(_ preset: AspectRatioPreset) {
        aspectRatio = preset.rawValue
        generateHapticFeedback()
    }

    func setTimerSeconds(_ timer: TimerSeconds) {
        timerCaptureSeconds = timer.rawValue
        generateHapticFeedback()
    }

    // MARK: - Video setting method
    func setVideoResolution(_ resolution: VideoResolution) {
        videoResolution = resolution
        generateHapticFeedback()
    }

    func setVideoFrameRate(_ frameRate: VideoFrameRate) {
        videoFrameRate = frameRate
        generateHapticFeedback()
    }

    func setVideoSaveFormat(_ format: VideoSaveFormat) {
        videoSaveFormat = format
        generateHapticFeedback()
    }

    // MARK: - How to set file naming format
    func setFileNamingFormat(_ format: FileNamingFormat) {
        fileNamingFormat = format
        generateHapticFeedback()
    }

    func setCustomFileNamingFormat(_ template: String) {
        customFileNamingFormat = template
        generateHapticFeedback()
    }

    func setFileNamingPrefix(_ prefix: String) {
        fileNamingPrefix = prefix
        generateHapticFeedback()
    }

    func setGuidelinesType(_ type: GuidelinesType) {
        guidelinesType = type
        generateHapticFeedback()
    }

    // MARK: - Audio setting method
    func setAudioNoiseReduction(_ enabled: Bool) {
        audioNoiseReductionEnabled = enabled
        generateHapticFeedback()
    }

    func setAudioPickupPattern(_ pattern: AudioPickupPattern) {
        audioPickupPattern = pattern
        generateHapticFeedback()
    }

    func toggleSetting<T>(_ keyPath: ReferenceWritableKeyPath<CameraSettingsState, T>) where T: Equatable {
        if T.self == Bool.self {
            let currentValue = self[keyPath: keyPath] as! Bool
            self[keyPath: keyPath] = !currentValue as! T
            generateHapticFeedback()
        }
    }

    /// Special handling for GPS settings.
    func toggleGPSSetting() {
        let permissionManager = PermissionManager.shared
        if saveGPSEnabled {
            // If it is currently on, close it directly.
            saveGPSEnabled = false
            generateHapticFeedback()
        } else {
            // If it is currently closed, check location permission first.
            if permissionManager.hasLocationPermission {
                // Already have permission, enable it directly.
                saveGPSEnabled = true
                generateHapticFeedback()
            } else {
                // No permission yet, request it.
                permissionManager.requestLocationPermission()
                _pendingGPSEnable = true
            }
        }
    }

    /// Tracks whether GPS should be enabled after permission is granted.
    private var _pendingGPSEnable = false

    /// Called after location permission is granted.
    func onLocationPermissionGranted() {
        if _pendingGPSEnable {
            saveGPSEnabled = true
            _pendingGPSEnable = false
            generateHapticFeedback()
        }
    }

    // MARK: - Automation convenience methods
    // The collection logic related to filtering is managed by FilterManager and is not maintained in the setting state.
    func generateHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// MARK: - notification extension
extension Notification.Name {
    static let videoResolutionDidChange = Notification.Name("videoResolutionDidChange")
    static let videoFrameRateDidChange = Notification.Name("videoFrameRateDidChange")
    static let videoStabilizationDidChange = Notification.Name("videoStabilizationDidChange")
    static let audioSettingsDidChange = Notification.Name("audioSettingsDidChange")
}
