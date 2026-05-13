import AVFoundation
import SwiftData
import SwiftUI

// MARK: - Camera Parameter Type

enum CameraParameterType: CaseIterable {
    case iso
    case shutterSpeed
    case focus
    case exposure
    case whiteBalance

    var icon: String? {
        switch self {
        case .iso: return nil
        case .shutterSpeed: return "camera.aperture"
        case .focus: return "scope"
        case .exposure: return "plus.forwardslash.minus"
        case .whiteBalance: return "thermometer.sun"
        }
    }

    var label: String? {
        switch self {
        case .iso: return "ISO"
        default: return nil
        }
    }

    var fixedWidthString: String {
        switch self {
        case .iso: return "88888"
        case .shutterSpeed: return "1/8888"
        case .focus: return "8.88"
        case .exposure: return "+8.8"
        case .whiteBalance: return "88888"
        }
    }
}

// MARK: - Parameter Configuration

struct ParameterConfig {
    let type: CameraParameterType
    let isAvailable: Bool
    let value: String
    let unit: String?
    let isHighlighted: Bool
    let initialization: (() -> Void)?
    let reset: (() -> Void)?
}

// MARK: - Camera Parameter View (Optimized)

struct CameraParameterView: View {
    @ObservedObject var deviceManager = CameraDeviceManager.shared
    @ObservedObject var focusManager: FocusManager
    @ObservedObject var exposureManager: ExposureManager
    @ObservedObject var viewState: CameraViewState

    @State private var activeParameter: CameraParameterType?

    init(focusManager: FocusManager,
         exposureManager: ExposureManager,
         viewState: CameraViewState)
    {
        self.focusManager = focusManager
        self.exposureManager = exposureManager
        self.viewState = viewState
    }

    private var isShowingSlider: Bool {
        activeParameter != nil
    }

    var body: some View {
        Group {
            if isShowingSlider {
                sliderView.padding(.horizontal, 24)
            } else {
                normalStatusView
            }
        }
    }

    @ViewBuilder
    private var sliderView: some View {
        if let parameter = activeParameter {
            SliderAreaContainer(content: {
                parameterSliderView(for: parameter)
            }, isShowing: Binding(
                get: { activeParameter != nil },
                set: { newValue in
                    if !newValue {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activeParameter = nil
                        }
                    }
                }
            ))
            .frame(height: 56) // Fixed height to match `normalStatusView`
        }
    }

    @ViewBuilder
    private func parameterSliderView(for parameter: CameraParameterType) -> some View {
        switch parameter {
        case .iso:
            ISOSlider(
                exposureManager: exposureManager,
                iso: $exposureManager.manualISO,
                range: exposureManager.getISORange()
            )
        case .shutterSpeed:
            ShutterSpeedSlider(
                exposureManager: exposureManager,
                shutterSpeed: $exposureManager.manualShutterSpeed,
                range: exposureManager.getShutterSpeedRange()
            )
        case .focus:
            FocusSlider(
                focusManager: focusManager,
                position: $focusManager.manualFocusPosition,
                range: focusManager.getFocusRange()
            )
        case .exposure:
            ExposureCompensationSlider(
                exposureCompensation: $exposureManager.exposureCompensation,
                range: exposureManager.getExposureCompensationRange()
            )
        case .whiteBalance:
            TemperatureSlider(
                whiteBalanceManager: deviceManager.whiteBalanceManager,
                temperature: Binding(
                    get: { deviceManager.whiteBalanceManager.manualTemperature },
                    set: { deviceManager.whiteBalanceManager.manualTemperature = $0 }
                ),
                range: deviceManager.whiteBalanceManager.getTemperatureRange()
            )
        }
    }

    private var normalStatusView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableParameters, id: \.type) { config in
                    if config.isAvailable {
                        ParameterButton(config: config, viewState: viewState, action: {
                            provideHapticFeedback()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                config.initialization?()
                                activeParameter = config.type
                            }
                        }, onLongPress: {
                            provideHapticFeedback(style: .light)
                            config.reset?()
                        })
                    }
                }
            }
            .padding(.leading, 24)
        }
    }

    private var availableParameters: [ParameterConfig] {
        [
            ParameterConfig(
                type: .iso,
                isAvailable: exposureManager.isParametersAvailable && exposureManager.canAdjustISO,
                value: CameraParameterFormatter.formatISOValue(Double(exposureManager.currentISO)),
                unit: nil,
                isHighlighted: exposureManager.isManualISOMode,
                initialization: { exposureManager.manualISO = exposureManager.currentISO },
                reset: { exposureManager.enableAutoISO() }
            ),
            ParameterConfig(
                type: .shutterSpeed,
                isAvailable: exposureManager.isParametersAvailable && exposureManager.canAdjustShutterSpeed,
                value: CameraParameterFormatter.formatShutterSpeed(Double(exposureManager.currentShutterSpeed)),
                unit: "S",
                isHighlighted: exposureManager.isManualShutterSpeedMode,
                initialization: { exposureManager.manualShutterSpeed = exposureManager.currentShutterSpeed },
                reset: { exposureManager.enableAutoShutterSpeed() }
            ),
            ParameterConfig(
                type: .focus,
                isAvailable: exposureManager.isParametersAvailable && focusManager.canAdjustFocus,
                value: String(format: "%.2f", focusManager.currentLensPosition),
                unit: nil,
                isHighlighted: focusManager.isManualFocusMode,
                initialization: { focusManager.manualFocusPosition = focusManager.currentLensPosition },
                reset: { focusManager.enableAutoFocusMode() }
            ),
            ParameterConfig(
                type: .exposure,
                isAvailable: exposureManager.isParametersAvailable && exposureManager.canAdjustExposure,
                value: CameraParameterFormatter.formatExposureCompensation(exposureManager.exposureCompensation),
                unit: nil,
                isHighlighted: exposureManager.exposureCompensation != 0,
                initialization: nil,
                reset: { exposureManager.exposureCompensation = 0.0 }
            ),
            ParameterConfig(
                type: .whiteBalance,
                isAvailable: exposureManager.isParametersAvailable,
                value: CameraParameterFormatter.formatWhiteBalanceValue(Double(deviceManager.getCurrentWhiteBalance().temperature)),
                unit: "K",
                isHighlighted: deviceManager.isManualWhiteBalanceMode,
                initialization: {
                    deviceManager.whiteBalanceManager.manualTemperature = deviceManager.whiteBalanceManager.currentTemperature
                    deviceManager.whiteBalanceManager.manualTint = deviceManager.whiteBalanceManager.currentTint
                },
                reset: { deviceManager.enableAutoWhiteBalance() }
            ),
        ]
    }

    private func provideHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Parameter Option Button Style

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

// MARK: - Parameter Button

private struct ParameterButton: View {
    let config: ParameterConfig
    let viewState: CameraViewState
    let action: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: action) {
            CameraParameterItem(
                icon: config.type.icon,
                label: config.type.label,
                value: config.value,
                unit: config.unit,
                isHighlighted: config.isHighlighted,
                fixedWidthString: config.type.fixedWidthString
            )
        }
        .buttonStyle(ParameterOptionButtonStyle(isSelected: config.isHighlighted))
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
    }
}

// MARK: - Status Parameter Item

private struct CameraParameterItem: View {
    var icon: String?
    var label: String?
    var value: String
    var unit: String?
    var isHighlighted: Bool = false
    var fixedWidthString: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
            } else if let label {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
            }

            HStack(spacing: 1) {
                ZStack(alignment: .center) {
                    if let fixedWidthString {
                        Text(fixedWidthString)
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .opacity(0)
                            .fixedSize()
                    }

                    Text(value)
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .fixedSize()
                }

                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .bold))
                }
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    private var textColor: Color {
        isHighlighted ? .black : .white
    }
}

// MARK: - Slider Area Container

private struct SliderAreaContainer<Content: View>: View {
    @ViewBuilder let content: Content
    @Binding var isShowing: Bool

    var body: some View {
        HStack(spacing: 8) {
            content.padding(.leading, 2)

            CloseButton(isShowing: $isShowing).padding(.trailing, 6)
        }
        .frame(height: 56)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Close Button (Optimized)

private struct CloseButton: View {
    @Binding var isShowing: Bool

    var body: some View {
        Button(
            action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                isShowing = false
            }
        ) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
