import AVFoundation
import UIKit

/// Utility to determine safe playback rates based on video properties and device capabilities
enum VideoPlaybackCapability {
    /// Calculate maximum safe playback rate based on video properties
    /// - Parameters:
    ///   - asset: The video asset to analyze
    /// - Returns: Maximum safe playback rate
    static func calculateMaxPlaybackRate(for asset: AVAsset) async -> Float {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return 1.0
        }

        // Get video properties
        guard let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate),
              let naturalSize = try? await videoTrack.load(.naturalSize)
        else {
            return 1.0
        }

        let preferredTransform = await (try? videoTrack.load(.preferredTransform)) ?? .identity
        let size = naturalSize.applying(preferredTransform)
        let resolution = CGSize(width: abs(size.width), height: abs(size.height))

        return calculateMaxPlaybackRate(resolution: resolution, frameRate: nominalFrameRate)
    }

    /// Calculate maximum safe playback rate based on video properties
    /// - Parameters:
    ///   - playerItem: The player item containing the video
    /// - Returns: Maximum safe playback rate
    static func calculateMaxPlaybackRate(for playerItem: AVPlayerItem) async -> Float {
        guard let videoTrack = try? await playerItem.asset.loadTracks(withMediaType: .video).first else {
            return 1.0
        }

        // Get video properties using async APIs
        guard let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate),
              let naturalSize = try? await videoTrack.load(.naturalSize)
        else {
            return 1.0
        }

        let preferredTransform = await (try? videoTrack.load(.preferredTransform)) ?? .identity
        let resolution = naturalSize.applying(preferredTransform)
        let size = CGSize(width: abs(resolution.width), height: abs(resolution.height))

        return calculateMaxPlaybackRate(resolution: size, frameRate: nominalFrameRate)
    }

    /// Calculate maximum safe playback rate based on resolution and frame rate
    /// - Parameters:
    ///   - resolution: Video resolution
    ///   - frameRate: Video frame rate (fps)
    /// - Returns: Maximum safe playback rate
    static func calculateMaxPlaybackRate(resolution: CGSize, frameRate: Float) -> Float {
        let pixelCount = resolution.width * resolution.height

        // Get device performance tier
        let deviceTier = getDevicePerformanceTier()

        // Define thresholds based on common resolutions and frame rates
        // These are conservative estimates to ensure smooth playback

        // 4K (3840x2160) = 8,294,400 pixels
        let is4K = pixelCount >= 8_000_000
        // 1080p (1920x1080) = 2,073,600 pixels
        let is1080p = pixelCount >= 2_000_000

        // High frame rate threshold (>= 50fps is considered high)
        let isHighFrameRate = frameRate >= 50.0

        // Calculate max playback rate based on pixel throughput and device capability
        if is4K {
            if isHighFrameRate {
                // 4K 60fps: Very demanding, limit to 2x even on high-end devices
                switch deviceTier {
                case .high:
                    return 2.0
                case .medium:
                    return 1.5
                case .low:
                    return 1.0
                }
            } else {
                // 4K 30fps: Still demanding, limit to 3x on high-end, 2x on others
                switch deviceTier {
                case .high:
                    return 3.0
                case .medium:
                    return 2.0
                case .low:
                    return 1.5
                }
            }
        } else if is1080p {
            if isHighFrameRate {
                // 1080p 60fps: Moderate demand
                switch deviceTier {
                case .high:
                    return 6.0
                case .medium:
                    return 3.0
                case .low:
                    return 2.0
                }
            } else {
                // 1080p 30fps: Low demand, can handle high speeds
                return 6.0
            }
        } else {
            // Lower resolutions: Can handle high speeds on all devices
            return 6.0
        }
    }

    /// Generate available playback rates up to the maximum safe rate
    /// - Parameter maxRate: Maximum safe playback rate
    /// - Returns: Array of available playback rates
    static func generatePlaybackRates(maxRate: Float) -> [Float] {
        let allRates: [Float] = [1.0, 1.5, 2.0, 3.0, 6.0]
        return allRates.filter { $0 <= maxRate }
    }

    /// Determine device performance tier
    /// - Returns: Performance tier (high, medium, or low)
    private static func getDevicePerformanceTier() -> PerformanceTier {
        // Use multiple signals to determine performance tier
        let processorCount = ProcessInfo.processInfo.processorCount
        let physicalMemory = ProcessInfo.processInfo.physicalMemory

        // Get device model identifier
        let identifier = getDeviceIdentifier()

        // Classify based on device identifier patterns
        // This approach is more maintainable than hard-coding specific models
        if identifier.contains("iPhone") {
            // Extract major version from identifier (e.g., "iPhone14,2" -> 14)
            if let majorVersion = extractMajorVersion(from: identifier, prefix: "iPhone") {
                // iPhone 13 and newer (iPhone14,x+) - A15+ chips
                if majorVersion >= 14 {
                    return .high
                }
                // iPhone XS to iPhone 12 (iPhone11,x to iPhone13,x) - A12-A14 chips
                if majorVersion >= 11 {
                    return .medium
                }
                // Older iPhones
                return .low
            }
        } else if identifier.contains("iPad") {
            // Extract major version from identifier
            if let majorVersion = extractMajorVersion(from: identifier, prefix: "iPad") {
                // iPad with M1/M2 or newer (iPad13,x+)
                if majorVersion >= 13 {
                    return .high
                }
                // Recent iPads (iPad11,x to iPad12,x)
                if majorVersion >= 11 {
                    return .medium
                }
                return .low
            }
        }

        // Fallback: Use CPU cores and RAM as performance indicators
        // Modern high-end devices: 6+ cores and 4GB+ RAM
        if processorCount >= 6, physicalMemory >= 4_000_000_000 {
            return .high
        }
        // Mid-range devices: 4+ cores and 2GB+ RAM
        if processorCount >= 4, physicalMemory >= 2_000_000_000 {
            return .medium
        }

        return .low
    }

    /// Get device model identifier
    /// - Returns: Device identifier string (e.g., "iPhone14,2")
    private static func getDeviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    /// Extract major version number from device identifier
    /// - Parameters:
    ///   - identifier: Device identifier (e.g., "iPhone14,2")
    ///   - prefix: Device prefix (e.g., "iPhone")
    /// - Returns: Major version number if found
    private static func extractMajorVersion(from identifier: String, prefix: String) -> Int? {
        guard let range = identifier.range(of: prefix) else { return nil }
        let modelPart = identifier[range.upperBound...]
        guard let commaIndex = modelPart.firstIndex(of: ",") else { return nil }
        return Int(modelPart[..<commaIndex])
    }

    enum PerformanceTier {
        case high
        case medium
        case low
    }
}
