import AVFoundation
import SwiftUI

// MARK: - design constants
private enum AudioSettingsDesign {
    static let cardColor = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255, opacity: 0.4)
    static let cardBorderColor = Color.white.opacity(0.08)
    static let cardCornerRadius: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let iconSize: CGFloat = 28
    static let iconCornerRadius: CGFloat = 8
}

private let settingsIconColor = Color.black.opacity(0.15)

// MARK: - Audio Settings View

struct AudioSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsState: CameraSettingsState
    @State private var supportedPatterns: [CameraSettingsState.AudioPickupPattern] = []

    var body: some View {
        ZStack {
            // Background.
            Color(white: 0.04).ignoresSafeArea()

            ScrollView {
                VStack(spacing: AudioSettingsDesign.sectionSpacing) {
                    // MARK: - Noise reduction settings
                    AudioSettingsSection(title: .audioSettingsNoiseReduction.localized) {
                        AudioToggleRow(
                            icon: "waveform.badge.minus",
                            iconColor: settingsIconColor,
                            title: .audioSettingsNoiseReduction.localized,
                            subtitle: .audioSettingsNoiseReductionDesc.localized,
                            isOn: $settingsState.audioNoiseReductionEnabled
                        )
                    }

                    // MARK: - radio mode
                    AudioSettingsSection(title: .audioSettingsPickupPattern.localized) {
                        ForEach(Array(supportedPatterns.enumerated()), id: \.element) { index, pattern in
                            if index > 0 {
                                AudioSettingsDivider()
                            }
                            AudioPatternRow(
                                pattern: pattern,
                                isSelected: settingsState.audioPickupPattern == pattern,
                                onTap: {
                                    AnalyticsManager.shared.log(.settingsAction(action: "select_audio_pattern_\(pattern.rawValue)"))
                                    settingsState.setAudioPickupPattern(pattern)
                                }
                            )
                        }

                        if supportedPatterns.isEmpty {
                            AudioInfoRow(
                                icon: "info.circle",
                                text: .audioPickupNotSupported.localized
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle(String.audioSettingsTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .trackScreen(name: "AudioSettings")
        .onChange(of: settingsState.audioNoiseReductionEnabled) { _, newValue in
            AnalyticsManager.shared.log(.settingsAction(action: "toggle_noise_reduction_\(newValue)"))
        }
        .onAppear {
            detectSupportedPatterns()
        }
    }

    // MARK: - Detect Supported Patterns

    private func detectSupportedPatterns() {
        let audioSession = AVAudioSession.sharedInstance()

        guard let availableInputs = audioSession.availableInputs,
              let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }),
              let dataSources = builtInMic.dataSources
        else {
            // Fall back to the baseline options when microphone capabilities are unavailable.
            supportedPatterns = [.ambient, .voice]
            return
        }

        var patterns: [CameraSettingsState.AudioPickupPattern] = []

        // Check which polar patterns are supported.
        let allSupportedPatterns = dataSources.compactMap(\.supportedPolarPatterns).flatMap { $0 }
        let uniquePatterns = Set(allSupportedPatterns)

        if uniquePatterns.contains(.omnidirectional) {
            patterns.append(.ambient)
        }
        if uniquePatterns.contains(.cardioid) {
            patterns.append(.voice)
        }
        if uniquePatterns.contains(.subcardioid) {
            patterns.append(.voiceEnhanced)
        }

        // If no pattern is detected, provide the baseline options.
        if patterns.isEmpty {
            patterns = [.ambient, .voice]
        }

        supportedPatterns = patterns
    }
}

// MARK: - Section Component

private struct AudioSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(paddingValue: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

// MARK: - Toggle Row

private struct AudioToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AudioIconView(icon: icon, color: iconColor)

                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                Spacer()

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.accentColor)
            }

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.gray)
                .padding(.leading, AudioSettingsDesign.iconSize + 12)
        }
        .padding(.horizontal, AudioSettingsDesign.cardPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Pattern Row

private struct AudioPatternRow: View {
    let pattern: CameraSettingsState.AudioPickupPattern
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AudioIconView(icon: pattern.systemIcon, color: settingsIconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.displayName)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)

                    Text(pattern.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, AudioSettingsDesign.cardPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Row

private struct AudioInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.gray)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            Spacer()
        }
        .padding(.horizontal, AudioSettingsDesign.cardPadding)
        .padding(.vertical, 12)
    }
}

// MARK: - Icon View

private struct AudioIconView: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: AudioSettingsDesign.iconSize, height: AudioSettingsDesign.iconSize)
            .background(color)
            .cornerRadius(AudioSettingsDesign.iconCornerRadius)
    }
}

// MARK: - Divider

private struct AudioSettingsDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.leading, 52)
    }
}

#Preview {
    NavigationStack {
        AudioSettingsView()
            .environmentObject(CameraSettingsState.shared)
    }
}
