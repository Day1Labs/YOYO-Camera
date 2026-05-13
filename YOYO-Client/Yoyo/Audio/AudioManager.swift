import AVFoundation
import Combine
import CoreMedia
import Foundation

/// Audio Manager
/// Responsible for calculating real-time audio levels and managing audio state (mute)
@MainActor
final class AudioManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AudioManager()

    // MARK: - Published Properties

    /// Current audio levels (0.0 - 1.0) for each channel
    /// Typically [Left, Right] for stereo, or [Mono, Mono] for mono input
    @Published private(set) var audioLevels: [Float] = [0.0, 0.0]

    /// Whether audio input is currently active (receiving buffers)
    @Published private(set) var isReceivingInput: Bool = false

    /// Whether audio is manually muted by user
    @Published var isMuted: Bool = false {
        didSet {
            muteState.value = isMuted
        }
    }

    // MARK: - Private Properties

    private final class MuteState: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Bool = false

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _value
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _value = newValue
            }
        }
    }

    private nonisolated let muteState = MuteState()

    private var lastUpdateTime: TimeInterval = 0
    private var lastBufferTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 0.1 // Update UI every 0.1s
    private var inactivityTimer: Timer?

    private init() {
        startInactivityCheck()
    }

    deinit {
        inactivityTimer?.invalidate()
    }

    private func startInactivityCheck() {
        // Check every 0.5s if we are still receiving data
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date().timeIntervalSince1970
                // If no buffer received for more than 0.5s, consider input inactive
                if now - self.lastBufferTime > 0.5 {
                    if self.isReceivingInput {
                        self.isReceivingInput = false
                        self.audioLevels = [0.0, 0.0]
                    }
                }
            }
        }
    }

    // MARK: - Public Methods

    /// Thread-safe access to mute state
    nonisolated var isAudioMuted: Bool {
        muteState.value
    }

    func toggleMute() {
        isMuted.toggle()
    }

    /// Process audio sample buffer to calculate level
    nonisolated func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let audioBufferList = CMSampleBufferGetDataBuffer(sampleBuffer)
        else {
            return
        }

        // Check if it contains audio data
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        guard mediaType == kCMMediaType_Audio else { return }

        // Get audio format description
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }

        // Get data pointer
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        guard CMBlockBufferGetDataPointer(audioBufferList, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let data = dataPointer
        else {
            return
        }

        let channelCount = Int(asbd.mChannelsPerFrame)
        var channelSums: [Float] = Array(repeating: 0.0, count: max(channelCount, 2))
        var frameCount = 0

        if asbd.mFormatID == kAudioFormatLinearPCM {
            if asbd.mBitsPerChannel == 16 {
                // 16-bit Integer PCM
                let totalSamples = totalLength / 2
                frameCount = totalSamples / channelCount
                let samples = UnsafeBufferPointer(start: data.withMemoryRebound(to: Int16.self, capacity: totalSamples) { $0 }, count: totalSamples)

                for i in 0 ..< frameCount {
                    for channel in 0 ..< channelCount {
                        let sampleIndex = i * channelCount + channel
                        if sampleIndex < samples.count {
                            let floatSample = Float(samples[sampleIndex]) / Float(Int16.max)
                            channelSums[channel] += floatSample * floatSample
                        }
                    }
                }
            } else if asbd.mBitsPerChannel == 32 {
                // 32-bit Float or Int PCM
                let totalSamples = totalLength / 4
                frameCount = totalSamples / channelCount

                if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                    // Float
                    let samples = UnsafeBufferPointer(start: data.withMemoryRebound(to: Float.self, capacity: totalSamples) { $0 }, count: totalSamples)

                    for i in 0 ..< frameCount {
                        for channel in 0 ..< channelCount {
                            let sampleIndex = i * channelCount + channel
                            if sampleIndex < samples.count {
                                let sample = samples[sampleIndex]
                                channelSums[channel] += sample * sample
                            }
                        }
                    }
                }
            }
        }

        // Calculate RMS for each channel
        var currentLevels: [Float] = []
        if frameCount > 0 {
            for channel in 0 ..< channelCount {
                let rms = sqrt(channelSums[channel] / Float(frameCount))
                // Convert to dB and normalize
                // Range: -60dB (0.0) to +3dB (1.0)
                // Total range: 63dB
                let db = 20 * log10(rms + 1e-9) // Avoid log(0)
                let normalized = max(0.0, min(1.0, (db + 60) / 63))
                currentLevels.append(normalized)
            }
        } else {
            currentLevels = Array(repeating: 0.0, count: channelCount)
        }

        // Normalize to stereo [Left, Right]
        let finalLevels: [Float]
        if channelCount == 1 {
            // Mono -> Stereo (duplicate)
            finalLevels = [currentLevels[0], currentLevels[0]]
        } else if channelCount >= 2 {
            // Stereo or more -> Take first two
            finalLevels = [currentLevels[0], currentLevels[1]]
        } else {
            finalLevels = [0.0, 0.0]
        }

        // Update UI on main thread, throttled
        let now = Date().timeIntervalSince1970

        Task { @MainActor in
            self.lastBufferTime = now
            self.isReceivingInput = true

            if now - self.lastUpdateTime >= self.updateInterval {
                // Apply smoothing to each channel
                var newLevels: [Float] = []
                for (index, currentLevel) in finalLevels.enumerated() {
                    let oldLevel = index < self.audioLevels.count ? self.audioLevels[index] : 0.0
                    if currentLevel > oldLevel {
                        newLevels.append(currentLevel)
                    } else {
                        newLevels.append(oldLevel * 0.8 + currentLevel * 0.2)
                    }
                }
                self.audioLevels = newLevels
                self.lastUpdateTime = now
            }
        }
    }

    func reset() {
        audioLevels = [0.0, 0.0]
        isReceivingInput = false
    }
}
