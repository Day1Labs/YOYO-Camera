
import Accelerate
import AVFoundation
import CoreImage
import CoreLocation
import CoreML
import SwiftUI
import Vision

// MARK: - analysis result types

enum AnalysisResult {
    case scene((type: SceneType, confidence: Float, identifier: String?))
    case objects([DetectedObject])
    case composition(CompositionAnalysis)
    case lighting(LightingAnalysisResult)
    case colors([UIColor])
}

// MARK: - analysis error types

enum AnalysisError: Error {
    case incompleteResults
    case analysisTimeout
    case deviceNotAvailable
}

// MARK: - scene analysis result

struct SceneAnalysis {
    let sceneType: SceneType
    let confidence: Float
    let timeOfDay: TimeOfDay
    let lightingCondition: LightingCondition
    let objectsDetected: [DetectedObject]
    let dominantColors: [UIColor]
    let composition: CompositionAnalysis
    // Added: exposure metering data for the EV control loop
    let averageBrightness: Float // 0..1 average brightness(linear)
    let histogram: HistogramAnalysis // histogram features(highlights/shadows/dynamic range)
    // Added: sensor data
    let currentTime: Date // current time
    let location: CLLocation? // Location (including latitude/longitude and altitude)

    /// Empty scene analysis result (used when image analysis is not required)
    static func empty(location: CLLocation?) -> SceneAnalysis {
        SceneAnalysis(
            sceneType: .general,
            confidence: 0,
            timeOfDay: .morning,
            lightingCondition: .normal,
            objectsDetected: [],
            dominantColors: [],
            composition: CompositionAnalysis.empty(),
            averageBrightness: 0.5,
            histogram: HistogramAnalysis.defaultAnalysis(),
            currentTime: Date(),
            location: location
        )
    }
}

struct AnalysisHistoryItem: Identifiable {
    let id = UUID()
    let analysis: SceneAnalysis
    let matchedRules: [AutomationRule]
    let timestamp: Date = .init()
}

// MARK: - SampleBufferProvider protocol

protocol SampleBufferProvider: AnyObject {
    func getCurrentSampleBuffer() -> CMSampleBuffer?
}

// MARK: - AI capture mode manager (Automation Manager)

@MainActor
final class CameraAutomationManager: ObservableObject {
    static let shared = CameraAutomationManager()

    @Published var isAnalyzing = false
    @Published var currentAnalysis: SceneAnalysis?
    @Published var suggestedSettings: CameraSettings?
    @Published var activeRules: [AutomationRule] = [] // Added: currently active rules
    @Published var analysisProgress: Float = 0.0
    @Published var analysisHistory: [AnalysisHistoryItem] = []
    @Published var executionHistory: [AutomationExecutionHistory] = []
    @Published var pendingConfirmation: PendingConfirmation? // rule pending confirmation

    /// rule execution time records(used for cooldown checks)
    private var lastExecutionTimes: [String: Date] = [:]

    // confirmation bubblecooldown time(cooldown after user cancellation/confirmation)
    private var confirmationCooldownUntil: Date?
    private let confirmationCooldownDuration: TimeInterval = 3.0 // 3-second cooldown

    let automationEngine = AutomationEngine()

    /// Location manager
    let locationManager = LocationManager.shared

    private var realTimeAnalysisTask: Task<Void, Never>?

    /// Real-time analysis configuration
    private let realTimeAnalysisInterval: TimeInterval = 2.0

    /// Settings manager
    var cameraSettings: CameraSettingsState { CameraSettingsState.shared }

    /// Convenient access to capture session state
    var isCaptureSessionActive: Bool {
        get { cameraSettings.isCaptureSessionActive }
        set { cameraSettings.isCaptureSessionActive = newValue }
    }

    var focusManager: FocusManager { .shared }
    var exposureManager: ExposureManager { .shared }
    weak var sampleBufferProvider: SampleBufferProvider?

    private init() {}

    // MARK: - Main feature methods

    /// Start real-time analysis
    private func startRealTimeAnalysis() {
        guard realTimeAnalysisTask == nil else { return }
        guard cameraSettings.isCaptureSessionActive else { return } // start only when capture mode is active

        // Check whether any rule requires location information
        if needsLocationForRules() {
            // request location permission(if not yet authorized)
            if locationManager.authorizationStatus() == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            // start location updates
            locationManager.startMonitoring()
        }

        realTimeAnalysisTask = Task { @MainActor in
            while !Task.isCancelled, cameraSettings.automationEnabled, cameraSettings.isCaptureSessionActive {
                // get the latest preview frame from SampleBufferProvider
                if let sampleBuffer = getCurrentSampleBuffer() {
                    await analyzeAndApply(from: sampleBuffer)
                }

                // control analysis frequency, avoid excessive resource usage
                try? await Task.sleep(nanoseconds: UInt64(realTimeAnalysisInterval * 1_000_000_000))
            }
        }
    }

    /// Check whether any rule requires location information
    private func needsLocationForRules() -> Bool {
        automationEngine.rules.contains { rule in
            rule.isEnabled && rule.conditions.contains { condition in
                switch condition {
                case .nearLocation, .insideRegion, .outsideRegion, .altitudeAbove, .altitudeBelow, .altitudeInRange:
                    return true
                default:
                    return false
                }
            }
        }
    }

    /// Stop real-time analysis
    private func stopRealTimeAnalysis() {
        realTimeAnalysisTask?.cancel()
        realTimeAnalysisTask = nil

        // stop location updates to save battery
        locationManager.stopMonitoring()
    }

    /// Automation is about to activate
    func activateAutomation() {
        // if real-time mode is enabled, start analysis
        if cameraSettings.automationEnabled {
            startRealTimeAnalysis()
        }
    }

    /// Automation is about to deactivate
    func deactivateAutomation() {
        stopRealTimeAnalysis()
    }

    /// Analyze in real time and apply settings
    private func analyzeAndApply(from sampleBuffer: CMSampleBuffer) async {
        guard !Task.isCancelled else { return }

        // set analysis state to in progress
        await MainActor.run {
            self.isAnalyzing = true
        }

        do {
            // use the optimized parallel analysis method
            let analysis = try await performAnalysis(from: sampleBuffer, withLogs: true)

            // print recognized objects
            let detectedObjects = analysis.objectsDetected
            if !detectedObjects.isEmpty {
                print("🎯 [DEBUG] AI实时物体检测:")
                print("   - 实时检测到物体数量: \(detectedObjects.count)")
                for (index, object) in detectedObjects.enumerated() {
                    print("   - 实时物体\(index + 1): \(object.label) (置信度: \(String(format: "%.1f", object.confidence * 100))%)")
                }
                let objectNames = detectedObjects.map { "\($0.label)(\(Int($0.confidence * 100))%)" }
                print("   - 实时物体列表: \(objectNames.joined(separator: ", "))")
            } else {
                print("🎯 [DEBUG] AI实时检测: 当前帧未检测到物体")
            }

            // Use AutomationEngine to generate the plan uniformly (with toast)
            let (plan, matchedRules) = automationEngine.composeSettings(for: analysis)
            let settings = plan.camera

            // filter out rules still in cooldown
            let rulesNotInCooldown = matchedRules.filter { !isRuleInCooldown($0) }

            // separate rules requiring confirmation from rules that can execute directly
            let rulesNeedingConfirmation = rulesNotInCooldown.filter { $0.requireConfirmation ?? true }
            let rulesForAutoExecution = rulesNotInCooldown.filter { !($0.requireConfirmation ?? true) }

            // record execution history
            let executionStartTime = Date()

            // update the current analysis result for UI display
            await MainActor.run {
                self.currentAnalysis = analysis
                self.suggestedSettings = settings
                self.activeRules = matchedRules

                // add to history
                let historyItem = AnalysisHistoryItem(
                    analysis: analysis,
                    matchedRules: matchedRules
                )
                self.analysisHistory.insert(historyItem, at: 0)
                // limit history length
                if self.analysisHistory.count > 50 {
                    self.analysisHistory.removeLast()
                }
            }

            // handle rules requiring confirmation
            if !rulesNeedingConfirmation.isEmpty {
                // generate separate settings for rules that need confirmation(with toast)
                let (pendingPlan, _) = automationEngine.composeSettings(for: analysis, limitedTo: rulesNeedingConfirmation)

                await MainActor.run {
                    // create a new one only when there is no pending confirmation and it is not in cooldown
                    if self.pendingConfirmation == nil, !self.isInConfirmationCooldown() {
                        self.pendingConfirmation = PendingConfirmation(
                            rules: rulesNeedingConfirmation,
                            settings: pendingPlan.camera,
                            toasts: pendingPlan.toasts,
                            analysis: analysis,
                            timestamp: Date(),
                            pendingFilterImports: pendingPlan.pendingFilterImports
                        )
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }

            // apply only rules that do not require confirmation
            if !rulesForAutoExecution.isEmpty {
                print("🚀 [DEBUG] 准备执行 \(rulesForAutoExecution.count) 条自动规则")
                for rule in rulesForAutoExecution {
                    print("   - 规则: \(rule.name)")
                }

                // Record rule execution time (used for cooldown)
                for rule in rulesForAutoExecution {
                    lastExecutionTimes[rule.id] = executionStartTime
                }

                let (autoPlan, _) = automationEngine.composeSettings(for: analysis, limitedTo: rulesForAutoExecution)
                await applySettings(autoPlan.camera, includeWhiteBalance: true,
                                    matchedRules: rulesForAutoExecution,
                                    executionStartTime: executionStartTime,
                                    analysis: analysis,
                                    toastMessages: autoPlan.toasts,
                                    pendingFilterImports: autoPlan.pendingFilterImports)
            } else {
                print("ℹ️ [DEBUG] 没有需要自动执行的规则")
            }
        } catch {
            if !Task.isCancelled {
                print("⚠️ 实时分析失败: \(error)")
            }
        }

        // analysis complete, reset analysis state
        await MainActor.run {
            self.isAnalyzing = false
        }
    }

    // The old generateSettingsForRules has been removed; AutomationEngine now provides this uniformly

    /// Confirm the pending rule to execute
    func confirmPendingRules() {
        print("🔵 [DEBUG] confirmPendingRules 被调用, pendingConfirmation = \(pendingConfirmation != nil ? "有值" : "nil")")
        guard let pending = pendingConfirmation else {
            print("🔵 [DEBUG] pendingConfirmation 为 nil，直接返回")
            return
        }

        let executionStartTime = Date()

        for rule in pending.rules {
            lastExecutionTimes[rule.id] = executionStartTime
        }

        Task {
            await applySettings(
                pending.settings,
                includeWhiteBalance: true,
                matchedRules: pending.rules,
                executionStartTime: executionStartTime,
                analysis: pending.analysis,
                triggerType: .confirmed,
                toastMessages: pending.toasts,
                pendingFilterImports: pending.pendingFilterImports
            )
        }

        finishPendingConfirmationLifecycle()
        print("✅ 用户确认执行规则: \(pending.ruleNames)")
    }

    /// Check whether the rule is cooling down
    private func isRuleInCooldown(_ rule: AutomationRule) -> Bool {
        guard rule.executionInterval > 0 else { return false }
        guard let lastTime = lastExecutionTimes[rule.id] else { return false }
        let elapsed = Date().timeIntervalSince(lastTime)
        let inCooldown = elapsed < rule.executionInterval
        if inCooldown {
            print("⏳ 规则 '\(rule.name)' 冷却中，剩余 \(Int(rule.executionInterval - elapsed)) 秒")
        }
        return inCooldown
    }

    /// Cancel the pending rule
    func dismissPendingRules() {
        print("🔴 [DEBUG] dismissPendingRules 被调用, pendingConfirmation = \(pendingConfirmation != nil ? "有值" : "nil")")
        guard let pending = pendingConfirmation else {
            print("🔴 [DEBUG] pendingConfirmation 为 nil，直接返回")
            return
        }

        // Use the unified history-recording API
        Task {
            await recordExecutionHistory(
                matchedRules: pending.rules,
                executionStartTime: Date(),
                analysis: pending.analysis,
                settings: pending.settings,
                triggerType: .cancelled
            )
        }

        finishPendingConfirmationLifecycle()
        print("❌ 用户取消执行规则: \(pending.ruleNames)")
    }

    /// Interrupt the analysis process
    func cancelAnalysis() {
        realTimeAnalysisTask?.cancel()
        realTimeAnalysisTask = nil
        isAnalyzing = false
        analysisProgress = 0.0
        currentAnalysis = nil
        suggestedSettings = nil

        print("AI 分析已中断")
    }

    /// Manually execute a single rule once
    func executeRuleOnce(_ rule: AutomationRule) async -> Bool {
        // use the current analysis, or an empty analysis if unavailable(manual triggers should not depend on whether real-time analysis is running)
        let analysis = currentAnalysis ?? SceneAnalysis.empty(location: locationManager.currentLocation)

        // use the unified generation path to obtain settings and toast messages
        let (plan, _) = automationEngine.composeSettings(for: analysis, limitedTo: [rule])
        let settings = plan.camera

        // record execution history
        let executionStartTime = Date()

        // apply settings
        await applySettings(settings, includeWhiteBalance: true,
                            matchedRules: [rule],
                            executionStartTime: executionStartTime,
                            analysis: analysis,
                            triggerType: .manual,
                            toastMessages: plan.toasts,
                            pendingFilterImports: plan.pendingFilterImports)

        print("✅ 手动执行规则: \(rule.name)")
        return true
    }

    /// Trigger pre-capture automation
    func triggerBeforeCapture() async {
        guard cameraSettings.automationEnabled else { return }
        guard let analysis = currentAnalysis else { return }

        print("📸 [DEBUG] 触发拍摄前自动化")

        // use AutomationEngine to generate the pre-capture plan
        let (plan, matchedRules) = automationEngine.composeSettings(for: analysis, captureState: .beforeCapture)

        if !matchedRules.isEmpty {
            print("   - 匹配拍摄前规则: \(matchedRules.map(\.name).joined(separator: ", "))")
            await applySettings(plan.camera, includeWhiteBalance: true,
                                matchedRules: matchedRules,
                                executionStartTime: Date(),
                                analysis: analysis,
                                triggerType: .automatic,
                                toastMessages: plan.toasts,
                                pendingFilterImports: plan.pendingFilterImports)
        }
    }

    /// Trigger post-capture automation
    func triggerAfterCapture() async {
        guard cameraSettings.automationEnabled else { return }
        guard let analysis = currentAnalysis else { return }

        print("📸 [DEBUG] 触发拍摄后自动化")

        // use AutomationEngine to generate the post-capture plan
        let (plan, matchedRules) = automationEngine.composeSettings(for: analysis, captureState: .afterCapture)

        if !matchedRules.isEmpty {
            print("   - 匹配拍摄后规则: \(matchedRules.map(\.name).joined(separator: ", "))")
            await applySettings(plan.camera, includeWhiteBalance: true,
                                matchedRules: matchedRules,
                                executionStartTime: Date(),
                                analysis: analysis,
                                triggerType: .automatic,
                                toastMessages: plan.toasts,
                                pendingFilterImports: plan.pendingFilterImports)
        }
    }

    /// Apply camera settings uniformly
    private func applySettings(_ settings: CameraSettings,
                               includeWhiteBalance: Bool,
                               matchedRules: [AutomationRule] = [],
                               executionStartTime: Date = Date(),
                               analysis: SceneAnalysis? = nil,
                               triggerType: AutomationTriggerType = .automatic,
                               toastMessages: [(type: ToastType, message: String, duration: Double, customIcon: String?)] = [],
                               pendingFilterImports: [(url: String, displayName: String?)] = []) async
    {
        print("🎬 [DEBUG] applySettings 被调用")
        print("   - 匹配规则数: \(matchedRules.count)")
        if !matchedRules.isEmpty { print("   - 规则名称: \(matchedRules.map(\.name).joined(separator: ", "))") }
        print("   - settings.zoom: \(settings.zoom?.description ?? "nil")")
        print("   - settings.exposureBias: \(settings.exposureBias?.description ?? "nil")")
        print("   - settings.focusPoint: \(settings.focusPoint?.debugDescription ?? "nil")")
        print("   - settings.filter: \(settings.filter?.displayName ?? "nil")")
        print("   - settings.flashMode: \(settings.flashMode?.rawValue.description ?? "nil")")
        print("   - autoAdjustExposure: \(cameraSettings.autoAdjustExposure)")
        print("   - autoAdjustFocus: \(cameraSettings.autoAdjustFocus)")

        applyFilter(from: settings)
        applyFocus(from: settings)
        applyExposureBias(from: settings)

        if let zoom = settings.zoom {
            print("🔍 [DEBUG] 准备应用缩放: \(zoom)x")
            await applyZoom(zoom)
        }

        applyISO(from: settings)
        applyShutterSpeed(from: settings)
        applyWhiteBalance(from: settings, includeWhiteBalance: includeWhiteBalance)
        applyFlash(from: settings)

        // handle filter import(import sequentially, with the last one applied)
        for filterImport in pendingFilterImports {
            await importFilterFromURL(filterImport.url, displayName: filterImport.displayName)
        }

        await recordExecutionHistory(
            matchedRules: matchedRules,
            executionStartTime: executionStartTime,
            analysis: analysis,
            settings: settings,
            triggerType: triggerType
        )

        await showToastMessages(toastMessages)
    }

    private func applyFilter(from settings: CameraSettings) {
        if let filter = settings.filter, cameraSettings.autoSelectFilter {
            FilterManager.shared.selectedFilter = filter
            print("AI 应用滤镜: \(filter.displayName)")
        }
    }

    /// Import a filter from URL and apply it
    private func importFilterFromURL(_ urlString: String, displayName: String?) async {
        guard cameraSettings.autoSelectFilter else {
            print("⏭️ 跳过滤镜导入: autoSelectFilter 未启用")
            return
        }

        print("📥 [DEBUG] 开始从 URL 导入滤镜: \(urlString)")

        // check whether a filter with the same name already exists(determine by the filename in the URL)
        let fileName = URL(string: urlString)?.lastPathComponent ?? ""
        let existingFilter = CustomFilterManager.shared.customFilters.first {
            $0.lutFileName == fileName || $0.name == (displayName ?? fileName)
        }

        if let existing = existingFilter {
            // filter already exists, apply it directly
            print("✅ 滤镜已存在，直接应用: \(existing.name)")
            await MainActor.run {
                FilterManager.shared.selectCustomFilter(existing)
                CameraViewState.shared.showToast(
                    type: .info,
                    message: String.automationFilterAlreadyExists.localized(existing.name),
                    duration: 2.0
                )
            }
            return
        }

        // download and import the filter
        await withCheckedContinuation { continuation in
            CustomFilterManager.shared.importFilter(fromRemote: urlString) { result in
                Task { @MainActor in
                    switch result {
                    case let .success(filter):
                        // if a custom name is provided, update the filter name
                        var importedFilter = filter
                        if let customName = displayName, !customName.isEmpty {
                            if let index = CustomFilterManager.shared.customFilters.firstIndex(where: { $0.id == filter.id }) {
                                CustomFilterManager.shared.customFilters[index].name = customName
                                CustomFilterManager.shared.saveFilters()
                                importedFilter = CustomFilterManager.shared.customFilters[index]
                            }
                        }

                        print("✅ 滤镜导入成功: \(importedFilter.name)")
                        FilterManager.shared.selectCustomFilter(importedFilter)
                        CameraViewState.shared.showToast(
                            type: .success,
                            message: String.automationFilterImportSuccess.localized(importedFilter.name),
                            duration: 2.0
                        )

                    case let .failure(error):
                        print("❌ 滤镜导入失败: \(error.localizedDescription)")
                        CameraViewState.shared.showToast(
                            type: .error,
                            message: String.automationFilterImportFailed.localized,
                            duration: 3.0
                        )
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func currentFocusDevicePoint() -> CGPoint? {
        let fm = focusManager
        let current = fm.focusPoint
        return CGPoint(
            x: (current.x - fm.previewOrigin.x) / (fm.previewSize.width == 0 ? 1 : fm.previewSize.width),
            y: (current.y - fm.previewOrigin.y) / (fm.previewSize.height == 0 ? 1 : fm.previewSize.height)
        )
    }

    private func applyFocus(from settings: CameraSettings) {
        guard let focusPoint = settings.focusPoint, cameraSettings.autoAdjustFocus else { return }

        if let currentDevicePoint = currentFocusDevicePoint() {
            let diff = sqrt(pow(focusPoint.x - currentDevicePoint.x, 2) + pow(focusPoint.y - currentDevicePoint.y, 2))
            let threshold: CGFloat = 0.05
            if diff > threshold {
                focusManager.focusAtDevicePoint(focusPoint)
                print("AI 应用对焦点: \(focusPoint) (差异: \(String(format: "%.3f", diff)))")
            } else {
                print("AI 跳过对焦点应用: 差异过小 (\(String(format: "%.3f", diff)))")
            }
        } else {
            focusManager.focusAtDevicePoint(focusPoint)
            print("AI 应用对焦点: \(focusPoint)")
        }
    }

    private func applyExposureBias(from settings: CameraSettings) {
        guard let exposureBias = settings.exposureBias, cameraSettings.autoAdjustExposure else {
            print("❌ [DEBUG] 曝光补偿未应用:")
            print("   - settings.exposureBias 有值: \(settings.exposureBias != nil)")
            print("   - autoAdjustExposure: \(cameraSettings.autoAdjustExposure)")
            return
        }

        let current = exposureManager.exposureCompensation
        let diff = abs(exposureBias - current)
        print("📸 [DEBUG] 曝光补偿检查:")
        print("   - 目标曝光: \(exposureBias)")
        print("   - 当前曝光: \(current)")
        print("   - 差异: \(String(format: "%.2f", diff)) EV")

        let threshold: Float = 0.1
        if diff > threshold {
            let maxBias = Float(cameraSettings.maxExposureBias)
            let clamped = min(max(exposureBias, -maxBias), maxBias)
            let em = exposureManager
            print("   - 🔧 通过 ExposureManager 应用曝光补偿")
            em.exposureCompensation = clamped
            print("✅ AI 应用曝光补偿: \(clamped) (差异: \(String(format: "%.2f", diff)) EV)")
        } else {
            print("⏭️ AI 跳过曝光补偿应用: 差异过小 (\(String(format: "%.2f", diff)) EV)")
        }
    }

    private func applyISO(from settings: CameraSettings) {
        guard let iso = settings.iso, cameraSettings.autoAdjustISO else { return }
        let current = exposureManager.currentISO
        let diff = abs(Float(iso) - current)
        let threshold: Float = 50.0
        if diff > threshold {
            exposureManager.enableManualISO()
            let clamped = min(Float(iso), Float(cameraSettings.maxISO))
            exposureManager.adjustISO(clamped)
            print("AI 应用 ISO: \(clamped) (差异: \(String(format: "%.0f", diff))) (上限: \(cameraSettings.maxISO))")
        } else {
            print("AI 跳过 ISO 应用: 差异过小 (\(String(format: "%.0f", diff)))")
        }
    }

    private func applyShutterSpeed(from settings: CameraSettings) {
        guard let shutterSpeed = settings.shutterSpeed, cameraSettings.autoAdjustShutterSpeed else { return }
        let current = exposureManager.currentShutterSpeed
        let newValue = CMTimeGetSeconds(shutterSpeed)
        let diff = abs(newValue - current)
        let threshold = 1.0 / 60.0
        if diff > threshold {
            exposureManager.enableManualShutterSpeed()
            let clamped = max(newValue, cameraSettings.minShutterSpeed)
            exposureManager.adjustShutterSpeed(clamped)
            print("AI 应用快门速度: 1/\(Int(1.0 / clamped))s (差异: \(String(format: "%.3f", diff))s) (最慢: 1/\(Int(1.0 / cameraSettings.minShutterSpeed))s)")
        } else {
            print("AI 跳过快门速度应用: 差异过小 (\(String(format: "%.3f", diff))s)")
        }
    }

    private func applyWhiteBalance(from settings: CameraSettings, includeWhiteBalance: Bool) {
        guard includeWhiteBalance, let wb = settings.whiteBalance, cameraSettings.autoAdjustWhiteBalance else { return }
        let currentTemp = CameraDeviceManager.shared.whiteBalanceManager.currentTemperature
        let currentTint = CameraDeviceManager.shared.whiteBalanceManager.currentTint
        let tempDiff = abs(wb.temperature - currentTemp)
        let tintDiff = abs(wb.tint - currentTint)
        let tempThreshold: Float = 50.0
        let tintThreshold: Float = 1.0
        if tempDiff > tempThreshold || tintDiff > tintThreshold {
            CameraDeviceManager.shared.whiteBalanceManager.enableManualMode()
            CameraDeviceManager.shared.setWhiteBalance(temperature: wb.temperature, tint: wb.tint)
            print("AI 应用白平衡: 温度=\(wb.temperature)K (差异: \(String(format: "%.0f", tempDiff))K), 色调=\(wb.tint) (差异: \(String(format: "%.1f", tintDiff)))")
        } else {
            print("AI 跳过白平衡应用: 差异过小 (色温差异: \(String(format: "%.0f", tempDiff))K, 色调差异: \(String(format: "%.1f", tintDiff)))")
        }
    }

    private func applyFlash(from settings: CameraSettings) {
        guard let flashMode = settings.flashMode else { return }

        if cameraSettings.currentCaptureMode == .movie {
            switch flashMode {
            case .auto:
                return
            case .on, .off:
                let enabled = (flashMode == .on)
                if cameraSettings.torchEnabled != enabled {
                    cameraSettings.torchEnabled = enabled
                    CameraDeviceManager.shared.setTorch(enabled: enabled)
                    print("AI 应用手电筒设置: \(enabled ? "开启" : "关闭")")
                }
            @unknown default:
                return
            }
        } else {
            if cameraSettings.flashMode != flashMode {
                cameraSettings.flashMode = flashMode
                print("AI 应用闪光灯模式: \(flashMode.rawValue)")
            }
        }
    }

    private func showToastMessages(_ messages: [(type: ToastType, message: String, duration: Double, customIcon: String?)]) async {
        guard !messages.isEmpty else { return }
        await MainActor.run {
            for info in messages {
                CameraViewState.shared.showToast(
                    type: info.type,
                    message: info.message,
                    duration: info.duration,
                    customIcon: info.customIcon
                )
            }
        }
    }

    private func isInConfirmationCooldown() -> Bool {
        confirmationCooldownUntil.map { Date() < $0 } ?? false
    }

    private func finishPendingConfirmationLifecycle() {
        pendingConfirmation = nil
        confirmationCooldownUntil = Date().addingTimeInterval(confirmationCooldownDuration)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// get the current preview frame
    private func getCurrentSampleBuffer() -> CMSampleBuffer? {
        sampleBufferProvider?.getCurrentSampleBuffer()
    }

    // MARK: - basic analysis methods

    private func analyzeLighting(from sampleBuffer: CMSampleBuffer) async -> LightingAnalysisResult {
        await LightingAnalyzer.getLightingAnalysis(from: sampleBuffer)
    }

    private func analyzeComposition(from sampleBuffer: CMSampleBuffer) async -> CompositionAnalysis {
        await CompositionAnalyzer.analyzeComposition(from: sampleBuffer)
    }

    private func analyzeColors(from sampleBuffer: CMSampleBuffer) async -> [UIColor] {
        await ColorAnalyzer.analyzeColors(from: sampleBuffer, maxColors: 5)
    }

    // MARK: - smart zoom

    /// intelligently apply zoom suggestions
    private func applyZoom(_ suggestedZoom: Double) async {
        let currentZoom = CameraDeviceManager.shared.zoomManager.deviceZoomFactor
        let zoomDifference = abs(suggestedZoom - currentZoom)

        print("🔎 [DEBUG] applyZoom:")
        print("   - 建议缩放: \(suggestedZoom)x")
        print("   - 当前缩放: \(currentZoom)x")
        print("   - 差异: \(String(format: "%.2f", zoomDifference))x")

        // do not adjust if the difference is very small
        if zoomDifference < 0.2 {
            print("⏭️ [DEBUG] 缩放差异过小，跳过")
            return
        }

        // handle zoom according to user settings
        print("✅ [DEBUG] 自动应用缩放: \(suggestedZoom)x")
        CameraDeviceManager.shared.zoomManager.setZoomFactor(suggestedZoom)
    }

    // MARK: - core parallel analysis method

    /// Optimized parallel analysis method (runs on demand to avoid unnecessary analysis)
    private func performAnalysis(from sampleBuffer: CMSampleBuffer, withLogs: Bool) async throws -> SceneAnalysis {
        guard !Task.isCancelled else { throw CancellationError() }

        let requirements = automationEngine.analysisRequirements

        // return the default analysis result if no analysis is required
        guard requirements.needsAnyAnalysis else {
            if withLogs {
                print("⏭️ [DEBUG] 无分析需求，跳过图像分析")
            }
            return SceneAnalysis.empty(location: locationManager.currentLocation)
        }

        if withLogs {
            print("📊 [DEBUG] 按需分析: objects=\(requirements.needsObjectDetection), composition=\(requirements.needsComposition), lighting=\(requirements.needsLighting), colors=\(requirements.needsColors)")
        }

        return try await withThrowingTaskGroup(of: AnalysisResult.self) { group in
            var totalTasks = 0

            // add analysis tasks as needed
            if requirements.needsObjectDetection {
                group.addTask { await .objects(ObjectDetector.detectObjects(from: sampleBuffer)) }
                totalTasks += 1
            }
            if requirements.needsComposition {
                group.addTask { await .composition(self.analyzeComposition(from: sampleBuffer)) }
                totalTasks += 1
            }
            if requirements.needsLighting {
                group.addTask { await .lighting(self.analyzeLighting(from: sampleBuffer)) }
                totalTasks += 1
            }
            if requirements.needsColors {
                group.addTask { await .colors(self.analyzeColors(from: sampleBuffer)) }
                totalTasks += 1
            }

            // collect results
            var results = AnalysisResults()
            var completedTasks = 0

            for try await result in group {
                guard !Task.isCancelled else { throw CancellationError() }

                results.update(with: result)

                completedTasks += 1
                if totalTasks > 0 {
                    await MainActor.run {
                        self.analysisProgress = Float(completedTasks) / Float(totalTasks)
                    }
                }
            }

            // Perform scene analysis based on object detection results (only when needed)
            if requirements.needsSceneClassification, let objects = results.objects {
                let sceneResult = SceneClassifier.classifySceneFromObjects(objects)
                results.scene = sceneResult
            }

            return try results.buildSceneAnalysis(location: self.locationManager.currentLocation, requirements: requirements)
        }
    }

    /// Analysis result collector
    private struct AnalysisResults {
        var scene: (type: SceneType, confidence: Float, identifier: String?)?
        var objects: [DetectedObject]?
        var composition: CompositionAnalysis?
        var lighting: LightingAnalysisResult?
        var colors: [UIColor]?

        mutating func update(with result: AnalysisResult) {
            switch result {
            case let .scene(s): scene = s
            case let .objects(o): objects = o
            case let .composition(c): composition = c
            case let .lighting(l): lighting = l
            case let .colors(c): colors = c
            }
        }

        func buildSceneAnalysis(location: CLLocation?, requirements: AnalysisRequirements? = nil) throws -> SceneAnalysis {
            // build on demand: check only the fields actually needed
            let req = requirements ?? AnalysisRequirements(
                needsObjectDetection: true,
                needsSceneClassification: true,
                needsComposition: true,
                needsLighting: true,
                needsColors: true
            )

            // verify that the required analysis results exist
            if req.needsSceneClassification, scene == nil {
                throw AnalysisError.incompleteResults
            }
            if req.needsObjectDetection, objects == nil {
                throw AnalysisError.incompleteResults
            }
            if req.needsComposition, composition == nil {
                throw AnalysisError.incompleteResults
            }
            if req.needsLighting, lighting == nil {
                throw AnalysisError.incompleteResults
            }
            if req.needsColors, colors == nil {
                throw AnalysisError.incompleteResults
            }

            return SceneAnalysis(
                sceneType: scene?.type ?? .general,
                confidence: scene?.confidence ?? 0,
                timeOfDay: lighting?.timeContext.timeOfDay ?? .morning,
                lightingCondition: lighting?.condition ?? .normal,
                objectsDetected: objects ?? [],
                dominantColors: colors ?? [],
                composition: composition ?? CompositionAnalysis.empty(),
                averageBrightness: lighting?.brightness ?? 0.5,
                histogram: lighting?.analysisDetails["histogram"] as? HistogramAnalysis ?? HistogramAnalysis.defaultAnalysis(),
                currentTime: Date(),
                location: location
            )
        }
    }

    /// record execution history
    private func recordExecutionHistory(
        matchedRules: [AutomationRule],
        executionStartTime: Date,
        analysis: SceneAnalysis?,
        settings _: CameraSettings,
        triggerType: AutomationTriggerType = .automatic
    ) async {
        guard let analysis else { return }

        let executionDuration = Date().timeIntervalSince(executionStartTime)

        // create an execution history entry
        for rule in matchedRules {
            AnalyticsManager.shared.log(.automationTriggered(ruleName: rule.name, triggerType: triggerType.rawValue))

            let triggeredConditions = rule.conditions.map(\.shortSummary)
            let executedActions = rule.actions.map(\.shortSummary)

            let executionRecord = AutomationExecutionHistory(
                id: UUID(),
                ruleName: rule.name,
                triggerType: triggerType,
                executionTime: executionStartTime,
                triggeredConditions: triggeredConditions,
                executedActions: executedActions,
                sceneContext: analysis.sceneType.rawValue,
                duration: executionDuration
            )

            await MainActor.run {
                self.executionHistory.insert(executionRecord, at: 0)
                // limit history length
                if self.executionHistory.count > 100 {
                    self.executionHistory.removeLast()
                }
            }
        }
    }
}
