import AVFoundation
import SwiftUI

/// audiosession manager
/// management AVAudioSession configurestate
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private var activeClients = 0
    private let lock = NSLock()

    // set(AppStorage)
    @AppStorage("audioNoiseReductionEnabled") private var noiseReductionEnabled = true
    @AppStorage("audioPickupPattern") private var pickupPatternRaw: String = "voice"

    private var pickupPattern: AVAudioSession.PolarPattern {
        switch pickupPatternRaw {
        case "ambient":
            return .omnidirectional
        case "voiceEnhanced":
            return .subcardioid
        default:
            return .cardioid
        }
    }

    private init() {
        // observeset
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChange),
            name: .audioSettingsDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleSettingsChange() {
        // configureaudiosession(ifcurrent)
        lock.lock()
        let hasActiveClients = activeClients > 0
        lock.unlock()

        if hasActiveClients {
            reconfigureSession()
        }
    }

    /// configureaudiosession(set)
    private func reconfigureSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // setmode
            let mode: AVAudioSession.Mode = noiseReductionEnabled ? .videoChat : .videoRecording

            try audioSession.setCategory(
                .playAndRecord,
                mode: mode,
                options: [.allowBluetooth, .defaultToSpeaker]
            )

            // configurepolar patternmode
            configureMicrophonePolarPattern(for: audioSession)

            print("✅ [AudioSessionManager] Reconfigured - NoiseReduction: \(noiseReductionEnabled), Pattern: \(pickupPatternRaw)")

        } catch {
            print("❌ [AudioSessionManager] Failed to reconfigure: \(error.localizedDescription)")
        }
    }

    /// audiosession
    /// need to useaudio
    func activate() {
        lock.lock()
        defer { lock.unlock() }

        if activeClients == 0 {
            configureAndActivateSession()
        }
        activeClients += 1
        print("🎤 [AudioSessionManager] Activate (Clients: \(activeClients))")
    }

    /// audiosession
    /// not thenneed to useaudio
    func deactivate() {
        lock.lock()
        defer { lock.unlock() }

        guard activeClients > 0 else {
            print("⚠️ [AudioSessionManager] Deactivate called but no active clients")
            return
        }

        activeClients -= 1
        print("🎤 [AudioSessionManager] Deactivate (Clients: \(activeClients))")

        if activeClients == 0 {
            deactivateSession()
        }
    }

    private func configureAndActivateSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // setmode
            // .videoChat - audio(,, auto)
            // .videoRecording - videorecordingmode, not
            let mode: AVAudioSession.Mode = noiseReductionEnabled ? .videoChat : .videoRecording

            try audioSession.setCategory(
                .playAndRecord,
                mode: mode,
                options: [.allowBluetooth, .defaultToSpeaker]
            )

            // set
            let preferredSampleRate = 48000.0
            try audioSession.setPreferredSampleRate(preferredSampleRate)

            // configuremicrophonepolar patternmode(set)
            configureMicrophonePolarPattern(for: audioSession)

            // recordingaudio IO, A/V sync
            try audioSession.setPreferredIOBufferDuration(0.005)

            // key: recording
            if #available(iOS 13.0, *) {
                try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            }

            try audioSession.setActive(true)

            let modeDescription = noiseReductionEnabled ? "videoChat (noise reduction enabled)" : "videoRecording"
            print("✅ [AudioSessionManager] Configured with \(modeDescription), pickup: \(pickupPatternRaw)")

        } catch {
            print("❌ [AudioSessionManager] Failed to configure AudioSession: \(error.localizedDescription)")
        }
    }

    /// configuremicrophonepolar patternmode
    private func configureMicrophonePolarPattern(for audioSession: AVAudioSession) {
        // getmicrophone
        guard let availableInputs = audioSession.availableInputs,
              let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic })
        else {
            print("⚠️ [AudioSessionManager] No built-in microphone found")
            return
        }

        // setinputmicrophone
        do {
            try audioSession.setPreferredInput(builtInMic)
        } catch {
            print("⚠️ [AudioSessionManager] Failed to set preferred input: \(error.localizedDescription)")
        }

        // checkwhethersupportpolar patternmodeconfigure
        guard let dataSources = builtInMic.dataSources, !dataSources.isEmpty else {
            print("ℹ️ [AudioSessionManager] No data sources available for polar pattern configuration")
            return
        }

        // audio pickupmodesetpolar patternmode
        let targetPattern = pickupPattern

        for dataSource in dataSources {
            if let patterns = dataSource.supportedPolarPatterns, patterns.contains(targetPattern) {
                do {
                    try dataSource.setPreferredPolarPattern(targetPattern)
                    try builtInMic.setPreferredDataSource(dataSource)
                    print("✅ [AudioSessionManager] Configured \(pickupPatternRaw) polar pattern for: \(dataSource.dataSourceName ?? "unknown")")
                    return
                } catch {
                    print("⚠️ [AudioSessionManager] Failed to set polar pattern: \(error.localizedDescription)")
                }
            }
        }

        // ifmodenot support, cardioid
        if targetPattern != .cardioid {
            for dataSource in dataSources {
                if let patterns = dataSource.supportedPolarPatterns, patterns.contains(.cardioid) {
                    do {
                        try dataSource.setPreferredPolarPattern(.cardioid)
                        try builtInMic.setPreferredDataSource(dataSource)
                        print("⚠️ [AudioSessionManager] Fallback to cardioid for: \(dataSource.dataSourceName ?? "unknown")")
                        return
                    } catch {
                        print("⚠️ [AudioSessionManager] Failed to set fallback polar pattern: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func deactivateSession() {
        do {
            // , andnotify App can restoreaudio
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ [AudioSessionManager] AudioSession deactivated")
        } catch {
            print("❌ [AudioSessionManager] Failed to deactivate AudioSession: \(error.localizedDescription)")
        }
    }
}
