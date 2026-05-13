import Foundation

/// cameraparametersformat, ensureUIEXIF
enum CameraParameterFormatter {
    // MARK: - shutter speedformat

    // MARK: -

    /// exposure, used for-0.0
    private static let exposureCompensationZeroThreshold: Float = 0.05

    /// shutter speed()- range
    /// propertiesuse, ensureuse
    /// range: 1/8000s 30s, range(1/30 - 1/2000)
    static let standardShutterSpeedStops: [Double] = [
        // Ultra-fast shutter (1/8000 - 1/2000) - suitable for sports photography and bright scenes
        1.0 / 8000, 1.0 / 6400, 1.0 / 5000, 1.0 / 4000, 1.0 / 3200, 1.0 / 2500, 1.0 / 2000,

        // Fast shutter (1/1600 - 1/400) - common range for everyday action shots
        1.0 / 1600, 1.0 / 1250, 1.0 / 1000, 1.0 / 800, 1.0 / 640, 1.0 / 500, 1.0 / 400,

        // (1/320 - 1/125)- range
        1.0 / 320, 1.0 / 250, 1.0 / 200, 1.0 / 160, 1.0 / 125,

        // (1/100 - 1/30)- capturerange
        1.0 / 100, 1.0 / 80, 1.0 / 60, 1.0 / 50, 1.0 / 40, 1.0 / 30,

        // (1/25 - 1/8)-, need to
        1.0 / 25, 1.0 / 20, 1.0 / 15, 1.0 / 13, 1.0 / 10, 1.0 / 8,

        // Slow shutter (1/6 - 0.8s) - tripod recommended
        1.0 / 6, 1.0 / 5, 1.0 / 4, 1.0 / 3, 0.4, 0.5, 0.6, 0.8,

        // Long exposure (1s - 30s) - suitable for long exposure, light painting, and star trails
        1.0, 1.3, 1.6, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 13.0, 15.0, 20.0, 25.0, 30.0,
    ]

    /// shutter speed
    private static func roundToNearestStop(_ duration: Double) -> Double {
        guard duration > 0, duration.isFinite else { return duration }

        // use
        let logValue = log2(duration)
        var minDistance = Double.infinity
        var nearestStop = duration

        for stop in standardShutterSpeedStops {
            let logStop = log2(stop)
            let distance = abs(logValue - logStop)
            if distance < minDistance {
                minDistance = distance
                nearestStop = stop
            }
        }

        return nearestStop
    }

    /// shutter speedformatmethod
    /// - Parameter duration: shutter speed()
    /// - Returns: format, not
    ///   - >= 1 seconds: "1"", "2"", "4""
    ///   - < 1 seconds: "1/4000", "1/60", "1/125"
    static func formatShutterSpeed(_ duration: Double) -> String {
        guard duration > 0, duration.isFinite else { return "-" }

        // Round the actual value to the nearest standard stop
        let val = roundToNearestStop(duration)

        if val >= 0.4 {
            // 0.4s:, 0.4", 1", 1.3", 10"
            // Do not show decimals for values greater than or equal to 10s; show one decimal place for values below 10s and remove any trailing `.0`
            let format = val >= 10 ? "%.0f\"" : "%.1f\""
            return String(format: format, val).replacingOccurrences(of: ".0\"", with: "\"")
        } else {
            // Below 0.4s: display as a fraction, such as `1/60`
            // use round Int error
            return "1/\(Int(round(1.0 / val)))"
        }
    }

    // MARK: - apertureformat

    /// apertureformatmethod
    /// - Parameter fNumber: aperture
    /// - Returns: format
    static func formatAperture(_ fNumber: Double) -> String {
        "f/\(String(format: "%.1f", fNumber))"
    }

    // MARK: - ISOformat

    /// ISOformatmethod
    /// - Parameter iso: ISO
    /// - Returns: format
    static func formatISO(_ iso: Double) -> String {
        "ISO\(Int(iso))"
    }

    // MARK: - focal lengthformat

    /// focal lengthformatmethod
    /// - Parameter focalLength: focal length(35mm)
    /// - Returns: format
    static func formatFocalLength(_ focalLength: Double) -> String {
        "\(Int(focalLength))mm"
    }

    // MARK: - white balanceformat

    /// white balanceformatmethod
    /// - Parameter temperature: temperature
    /// - Returns: format
    static func formatWhiteBalance(_ temperature: Double) -> String {
        "\(Int(temperature))K"
    }

    // MARK: - UIformat(not)

    /// formatfocal length(not mm)
    static func formatFocalLengthValue(_ focalLength: Double) -> String {
        trimTrailingZeros(from: String(format: "%.0f", focalLength))
    }

    /// formataperture(not f/)
    static func formatApertureValue(_ fNumber: Double) -> String {
        trimTrailingZeros(from: String(format: "%.1f", fNumber))
    }

    /// formatISO(not ISO)
    static func formatISOValue(_ iso: Double) -> String {
        "\(Int(iso))"
    }

    /// formatwhite balance(not K)
    static func formatWhiteBalanceValue(_ temperature: Double) -> String {
        "\(Int(temperature))"
    }

    /// formatexposure(EV)
    /// - Parameter ev: exposure
    /// - Returns: format, ("+1.5", "-2.0", "+0.0"), -0.0
    static func formatExposureCompensation(_ ev: Float) -> String {
        // If the absolute value is below the threshold (0.05), display it as `+0.0` to avoid showing `-0.0`
        let value = abs(ev) < exposureCompensationZeroThreshold ? 0.0 : ev
        return String(format: "%+.1f", value)
    }

    /// Remove trailing zeros and the decimal point
    private static func trimTrailingZeros(from value: String) -> String {
        guard value.contains(".") else { return value }
        var trimmed = value
        while trimmed.last == "0" {
            trimmed.removeLast()
        }
        if trimmed.last == "." {
            trimmed.removeLast()
        }
        return trimmed
    }

    // MARK: - EXIF

    /// EXIF
    /// - Parameters:
    ///   - iso: ISO
    ///   - aperture: aperture
    ///   - shutterSpeed: shutter speed
    ///   - focalLength: focal length
    /// - Returns: EXIF
    /// : focal lengthmm → aperturef/ → shutter speeds → ISO
    static func combineEXIFText(iso: Double?, aperture: Double?, shutterSpeed: Double?, focalLength: Double?) -> String {
        var components: [String] = []

        // 1. focal length
        if let focalLength {
            components.append(formatFocalLength(focalLength))
        }

        // 2. aperture
        if let aperture {
            components.append(formatAperture(aperture))
        }

        // 3. shutter speed
        if let shutterSpeed {
            components.append(formatShutterSpeed(shutterSpeed))
        }

        // 4. ISO
        if let iso {
            components.append(formatISO(iso))
        }

        return components.isEmpty ? "" : components.joined(separator: " ")
    }
}
