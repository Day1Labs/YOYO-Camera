import SwiftUI

struct AudioStatusView: View {
    @ObservedObject var audioManager: AudioManager
    var captureMode: CameraCaptureMode
    var hasMicrophonePermission: Bool

    /// Whether `AudioStatusView` should be shown
    private var shouldShow: Bool {
        // Always show in Live Photo or Movie mode because audio recording is required
        if captureMode == .livePhoto || captureMode == .movie {
            return true
        }
        // In Photo mode, show only when audio input is active or muted
        return audioManager.isReceivingInput || audioManager.isMuted
    }

    /// Compute the icon name
    private var iconName: String {
        if audioManager.isMuted || !hasMicrophonePermission {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }

    /// Compute the icon color
    private var iconColor: Color {
        if audioManager.isMuted {
            return .red // Muted by the user
        }
        if !hasMicrophonePermission {
            return .accentColor // No permission
        }
        return .white // Normal state
    }

    var body: some View {
        HStack(spacing: 4) {
            // Microphone Icon
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)

            // Audio Level Bars (Stereo)
            if !audioManager.isMuted, audioManager.isReceivingInput {
                VStack(spacing: 2) {
                    // Left Channel
                    HStack(alignment: .center, spacing: 2) {
                        Text("L")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 5)
                        AudioLevelBar(level: audioManager.audioLevels.count > 0 ? audioManager.audioLevels[0] : 0)
                            .frame(height: 5)
                    }

                    // Right Channel
                    HStack(alignment: .center, spacing: 2) {
                        Text("R")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 5)
                        AudioLevelBar(level: audioManager.audioLevels.count > 1 ? audioManager.audioLevels[1] : 0)
                            .frame(height: 5)
                    }
                }
                .frame(width: 36)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .contentShape(Rectangle())
        .cornerRadius(4)
        .opacity(shouldShow ? 1.0 : 0.0)
        .animation(.easeInOut, value: audioManager.isReceivingInput)
        .onTapGesture {
            audioManager.toggleMute()
        }
    }
}

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.2))
                    .frame(height: geometry.size.height)

                // Level
                RoundedRectangle(cornerRadius: 1)
                    .fill(levelColor)
                    .frame(width: geometry.size.width * CGFloat(min(1.0, level)), height: geometry.size.height)
                    .animation(.linear(duration: 0.1), value: level)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var levelColor: Color {
        // -60dB to -10dB (0.0 - 0.79): Green
        // -10dB to 0dB (0.79 - 0.95): AccentColor
        // 0dB to +3dB (0.95 - 1.0): Red
        if level > 0.95 {
            return .red
        } else if level > 0.79 {
            return .accentColor
        } else {
            return .green
        }
    }
}

#Preview {
    AudioStatusView(audioManager: AudioManager.shared, captureMode: .livePhoto, hasMicrophonePermission: true)
        .background(Color.black)
}
