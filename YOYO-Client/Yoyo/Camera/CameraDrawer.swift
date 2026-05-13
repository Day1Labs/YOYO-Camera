import SwiftUI

/// Camera control drawer showing quick tasks above and parameters below
struct CameraDrawer: View {
    @Binding var isExpanded: Bool

    // MARK: Dependencies

    @ObservedObject var deviceManager = CameraDeviceManager.shared
    @ObservedObject var focusManager: FocusManager
    @ObservedObject var exposureManager: ExposureManager
    @ObservedObject var automationManager: CameraAutomationManager
    @ObservedObject var quickTaskManager: QuickTaskManager = .shared
    @ObservedObject var settingsState: CameraSettingsState
    let viewState: CameraViewState

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    // MARK: Init

    init(
        isExpanded: Binding<Bool>,
        focusManager: FocusManager,
        exposureManager: ExposureManager,
        automationManager: CameraAutomationManager,
        viewState: CameraViewState,
        settingsState: CameraSettingsState
    ) {
        _isExpanded = isExpanded
        self.focusManager = focusManager
        self.exposureManager = exposureManager
        self.automationManager = automationManager
        self.viewState = viewState
        self.settingsState = settingsState
    }

    // MARK: Computed

    private var hasActiveManualAdjustments: Bool {
        exposureManager.isManualISOMode || exposureManager.isManualShutterSpeedMode
            || focusManager.isManualFocusMode || exposureManager.exposureCompensation != 0
            || deviceManager.isManualWhiteBalanceMode
    }

    // MARK: Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Parameter adjustment section
                VStack(alignment: .leading, spacing: 12) {
                    Text(String.cameraDrawerParameters.localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 24)

                    CameraParameterView(
                        focusManager: focusManager,
                        exposureManager: exposureManager,
                        viewState: viewState
                    )
                }

                Divider()
                    .background(Color.white.opacity(0.05))
                    .padding(.horizontal, 24)

                // Quick task section
                VStack(alignment: .leading, spacing: 12) {
                    Text(String.cameraDrawerQuickTasks.localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 24)

                    quickTaskContent
                }

                Divider()
                    .background(Color.white.opacity(0.05))
                    .padding(.horizontal, 24)

                if settingsState.currentCaptureMode == .movie {
                    // Resolution section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String.cameraSettingsVideoResolution.localized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 24)

                        CameraResolutionSelectionView(settingsState: settingsState)
                    }

                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.horizontal, 24)

                    // Frame rate section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String.cameraSettingsVideoFrameRate.localized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 24)

                        CameraFrameRateSelectionView(settingsState: settingsState)
                    }
                } else {
                    // Aspect ratio section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String.cameraSettingsAspectRatio.localized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 24)

                        CameraAspectRatioSelectionView(settingsState: settingsState)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.05))
                    .padding(.horizontal, 24)

                // Guidelines section
                VStack(alignment: .leading, spacing: 12) {
                    Text(String.cameraSettingsGuidelines.localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 24)

                    CameraGuidelinesSelectionView(settingsState: settingsState)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Quick Task Content

    private var quickTaskContent: some View {
        Group {
            if quickTaskManager.quickTaskRuleIds.isEmpty {
                emptyQuickTaskView
            } else {
                quickTaskScrollView
            }
        }
    }

    private var emptyQuickTaskView: some View {
        HStack {
            Button(action: {
                feedbackGenerator.impactOccurred()
                CameraViewState.shared.showingAutomationSettings = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                    Text(String.quickTaskEmpty.localized)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var quickTaskScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(quickTaskRules, id: \.id) { rule in
                    QuickTaskItem(
                        rule: rule,
                        automationManager: automationManager,
                        onRemove: {
                            feedbackGenerator.impactOccurred()
                            quickTaskManager.removeQuickTask(ruleId: rule.id)
                        },
                        viewState: viewState
                    )
                }
            }
            .padding(.leading, 24)
        }
    }

    private var quickTaskRules: [AutomationRule] {
        quickTaskManager.quickTaskRuleIds.compactMap { ruleId in
            automationManager.automationEngine.rules.first { $0.id == ruleId }
        }
    }

    // MARK: - Actions

    private func resetAllParameters() {
        feedbackGenerator.impactOccurred()
        exposureManager.enableAutoISO()
        exposureManager.enableAutoShutterSpeed()
        focusManager.enableAutoFocusMode()
        exposureManager.exposureCompensation = 0.0
        deviceManager.enableAutoWhiteBalance()
    }
}

// MARK: - QuickTaskItem (extracted from QuickTaskDrawer)

private struct QuickTaskItem: View {
    let rule: AutomationRule
    let automationManager: CameraAutomationManager
    let onRemove: () -> Void
    let viewState: CameraViewState

    @State private var isExecuting = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    private var taskIcon: String {
        rule.actions.first?.iconSystemName ?? "bolt.fill"
    }

    var body: some View {
        Button(action: executeTask) {
            HStack(spacing: 6) {
                ZStack {
                    if isExecuting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: taskIcon)
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                .frame(width: 18)

                Text(rule.name)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 56)
        }
        .buttonStyle(QuickTaskButtonStyle())
        .disabled(isExecuting)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label(String.quickTaskRemove.localized, systemImage: "trash")
            }
        }
    }

    private func executeTask() {
        guard !isExecuting else { return }
        isExecuting = true
        feedbackGenerator.impactOccurred()
        Task {
            let success = await automationManager.executeRuleOnce(rule)
            await MainActor.run {
                isExecuting = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

private struct QuickTaskButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct ParameterOptionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isSelected
                    ? Color.white.opacity(configuration.isPressed ? 0.75 : 0.82)
                    : Color.white.opacity(configuration.isPressed ? 0.2 : 0.12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Format Selection Content

private struct CameraResolutionSelectionView: View {
    @ObservedObject var settingsState: CameraSettingsState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CameraSettingsState.VideoResolution.allCases, id: \.self) { res in
                    Button {
                        settingsState.generateHapticFeedback()
                        settingsState.setVideoResolution(res)
                    } label: {
                        Text(res.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(settingsState.videoResolution == res ? .black : .white)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                    }
                    .buttonStyle(ParameterOptionButtonStyle(isSelected: settingsState.videoResolution == res))
                }
            }
            .padding(.leading, 24)
        }
    }
}

private struct CameraFrameRateSelectionView: View {
    @ObservedObject var settingsState: CameraSettingsState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CameraSettingsState.VideoFrameRate.allCases, id: \.self) { fps in
                    Button {
                        settingsState.generateHapticFeedback()
                        settingsState.setVideoFrameRate(fps)
                    } label: {
                        Text(fps.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(settingsState.videoFrameRate == fps ? .black : .white)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                    }
                    .buttonStyle(ParameterOptionButtonStyle(isSelected: settingsState.videoFrameRate == fps))
                }
            }
            .padding(.leading, 24)
        }
    }
}

private struct CameraAspectRatioSelectionView: View {
    @ObservedObject var settingsState: CameraSettingsState

    private let optionHeight: CGFloat = 56

    private func optionWidth(for preset: CameraSettingsState.AspectRatioPreset) -> CGFloat {
        optionHeight / CGFloat(preset.rawValue)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CameraSettingsState.AspectRatioPreset.allCases, id: \.self) { preset in
                    Button {
                        settingsState.generateHapticFeedback()
                        settingsState.setAspectRatio(preset)
                    } label: {
                        Text(preset.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(settingsState.currentAspectRatioPreset == preset ? .black : .white)
                            .frame(width: optionWidth(for: preset), height: optionHeight)
                    }
                    .buttonStyle(ParameterOptionButtonStyle(isSelected: settingsState.currentAspectRatioPreset == preset))
                }
            }
            .padding(.leading, 24)
        }
    }
}

private struct CameraGuidelinesSelectionView: View {
    @ObservedObject var settingsState: CameraSettingsState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CameraSettingsState.GuidelinesType.allCases, id: \.self) { type in
                    Button {
                        settingsState.generateHapticFeedback()
                        settingsState.setGuidelinesType(type)
                        AnalyticsManager.shared.log(.settingsAction(action: "select_guidelines_\(type.rawValue)"))
                    } label: {
                        ZStack {
                            if type == .off {
                                Image(systemName: "nosign")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(settingsState.guidelinesType == type ? .black : .white)
                            } else {
                                GuidelinesPreviewIcon(type: type)
                                    .stroke(settingsState.guidelinesType == type ? .black : .white, lineWidth: 1)
                                    .padding(12)
                            }
                        }
                        .frame(width: 72, height: 56)
                    }
                    .buttonStyle(ParameterOptionButtonStyle(isSelected: settingsState.guidelinesType == type))
                }
            }
            .padding(.leading, 24)
        }
    }
}

private struct GuidelinesPreviewIcon: Shape {
    let type: CameraSettingsState.GuidelinesType

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        switch type {
        case .off:
            break
        case .ruleOfThirds:
            drawRuleOfThirds(in: &path, width: width, height: height)
        case .ruleOfThirdsWithDiagonal:
            drawRuleOfThirds(in: &path, width: width, height: height)
            drawDiagonal(in: &path, width: width, height: height)
        case .goldenRatio:
            drawGoldenRatio(in: &path, width: width, height: height)
        case .grid6x4:
            drawGrid6x4(in: &path, width: width, height: height)
        }

        return path
    }

    private func drawRuleOfThirds(in path: inout Path, width: CGFloat, height: CGFloat) {
        for i in 1 ... 2 {
            let x = width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))

            let y = height * CGFloat(i) / 3
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }

    private func drawGoldenRatio(in path: inout Path, width: CGFloat, height: CGFloat) {
        let ratio: CGFloat = 0.618
        let points = [ratio, 1 - ratio]
        for p in points {
            let x = width * p
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))

            let y = height * p
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }

    private func drawGrid6x4(in path: inout Path, width: CGFloat, height: CGFloat) {
        for i in 1 ... 5 {
            let x = width * CGFloat(i) / 6
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        for i in 1 ... 3 {
            let y = height * CGFloat(i) / 4
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }

    private func drawDiagonal(in path: inout Path, width: CGFloat, height: CGFloat) {
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: height))
        path.move(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height))
    }
}

// MARK: - Preview

#Preview("Expanded - Parameters & QuickTasks") {
    let focusManager = FocusManager.shared
    let exposureManager = ExposureManager.shared
    let viewState = CameraViewState()

    exposureManager.setPreviewParameters(
        aperture: 1.8,
        shutterSpeed: 1.0 / 125.0,
        iso: 400,
        isLocked: false,
        compensation: 0.0
    )

    return CameraDrawer(
        isExpanded: .constant(true),
        focusManager: focusManager,
        exposureManager: exposureManager,
        automationManager: CameraAutomationManager.shared,
        viewState: viewState,
        settingsState: CameraSettingsState.shared
    )
    .background(Color.black)
}

#Preview("Collapsed") {
    CameraDrawer(
        isExpanded: .constant(false),
        focusManager: FocusManager.shared,
        exposureManager: ExposureManager.shared,
        automationManager: CameraAutomationManager.shared,
        viewState: CameraViewState(),
        settingsState: CameraSettingsState.shared
    )
    .background(Color.black)
}
