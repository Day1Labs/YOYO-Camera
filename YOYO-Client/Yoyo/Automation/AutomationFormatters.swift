import Foundation

enum AutomationFormatters {
    static func formatShutter(seconds: Double) -> String {
        if seconds >= 1.0 {
            return "\(trimNumber(seconds))s"
        } else if seconds > 0 {
            let denominator = Int(round(1.0 / seconds))
            return "1/\(denominator)s"
        } else {
            return "0s"
        }
    }

    static func formatZoom(_ value: Double) -> String {
        "\(trimNumber(value))x"
    }

    static func trimNumber(_ number: Double) -> String {
        let rounded = round(number * 100) / 100
        if abs(rounded - rounded.rounded()) < 0.0001 {
            return String(Int(rounded))
        } else {
            var s = String(format: "%.2f", rounded)
            if s.hasSuffix("00") {
                s.removeLast(2)
            } else if s.hasSuffix("0") {
                s.removeLast(1)
            }
            return s
        }
    }

    static func trimNumber(_ number: Float) -> String {
        trimNumber(Double(number))
    }

    static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return String.automationWeekdaySunday.localized
        case 2: return String.automationWeekdayMonday.localized
        case 3: return String.automationWeekdayTuesday.localized
        case 4: return String.automationWeekdayWednesday.localized
        case 5: return String.automationWeekdayThursday.localized
        case 6: return String.automationWeekdayFriday.localized
        case 7: return String.automationWeekdaySaturday.localized
        default: return "\(weekday)"
        }
    }

    static func monthName(_ month: Int) -> String {
        switch month {
        case 1: return String.automationMonthJanuary.localized
        case 2: return String.automationMonthFebruary.localized
        case 3: return String.automationMonthMarch.localized
        case 4: return String.automationMonthApril.localized
        case 5: return String.automationMonthMay.localized
        case 6: return String.automationMonthJune.localized
        case 7: return String.automationMonthJuly.localized
        case 8: return String.automationMonthAugust.localized
        case 9: return String.automationMonthSeptember.localized
        case 10: return String.automationMonthOctober.localized
        case 11: return String.automationMonthNovember.localized
        case 12: return String.automationMonthDecember.localized
        default: return "\(month)月"
        }
    }

    // MARK: - Shared UI Constants

    /// Common shutter denominators (kept consistent with UI options)
    static let shutterDenominators: [Int] = [
        4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 2, 1,
    ]

    /// Chinese weekday display (Sunday...Saturday), tuples contain numeric weekday and display text
    static var weekdays: [(Int, String)] {
        (1 ... 7).map { ($0, weekdayName($0)) }
    }

    /// Chinese month display (January...December), tuples contain numeric month and display text
    static let months: [(Int, String)] = (1 ... 12).map { ($0, monthName($0)) }

    /// Location selection radius options
    static let radiusOptions: [(String, Double)] = [
        ("50m", 50), ("100m", 100), ("200m", 200), ("500m", 500), ("1km", 1000),
    ]

    /// Prompt type options
    static let toastTypeOptions: [(ToastType, String)] = [
        (.success, String.automationToastSuccess.localized),
        (.info, String.automationToastInfo.localized),
        (.warning, String.automationToastWarning.localized),
        (.error, String.automationToastError.localized),
    ]

    /// Get the maximum number of days in a month (simplified, February fixed at 29 days)
    static func daysInMonth(_ month: Int) -> Int {
        switch month {
        case 2: return 29
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

enum ExecutionIntervalSupport {
    static func displayText(for seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return String.automationExecutionUnlimited.localized
        } else if seconds < 60 {
            return String.automationExecutionSeconds.localized(Int(seconds))
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            let secs = Int(seconds) % 60
            return secs > 0 ? String.automationIntervalMinutesSeconds.localized(mins, secs) : String.automationExecutionMinutes.localized(mins)
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            let mins = Int(seconds / 60) % 60
            return mins > 0 ? String.automationIntervalHoursMinutes.localized(hours, mins) : String.automationExecutionHours.localized(hours)
        } else {
            return String.automationIntervalMaxLabel.localized
        }
    }

    static func sliderToSeconds(_ value: Double, minSeconds: Double = 5, maxSeconds: Double = 86400) -> TimeInterval {
        let logMin = log(minSeconds)
        let logMax = log(maxSeconds)
        let logValue = logMin + value * (logMax - logMin)
        return exp(logValue)
    }

    static func secondsToSlider(_ seconds: TimeInterval, minSeconds: Double = 5, maxSeconds: Double = 86400) -> Double {
        let clamped = Swift.max(minSeconds, Swift.min(maxSeconds, seconds))
        let logMin = log(minSeconds)
        let logMax = log(maxSeconds)
        return (log(clamped) - logMin) / (logMax - logMin)
    }
}
