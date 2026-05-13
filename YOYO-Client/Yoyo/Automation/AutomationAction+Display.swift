import AVFoundation
import Foundation

extension AutomationAction: AutomationDisplayRepresentable {
    var iconSystemName: String {
        switch self {
        case .setZoom, .multiplyZoom, .clampZoom:
            return "magnifyingglass"
        case .setExposureBias, .addExposureBias:
            return "sun.max"
        case .setFlashMode, .setFlashModeIfAuto:
            return "bolt.fill"
        case .focusOnSubject, .focusOnRuleOfThirds:
            return "scope"
        case .setFilter:
            return "camera.filters"
        case .importFilterFromURL:
            return "arrow.down.circle"
        case .setWhiteBalance, .setWhiteBalanceTemperature, .setWhiteBalanceTint, .adjustWhiteBalanceTemperature, .adjustWhiteBalanceTint:
            return "thermometer.sun"
        case .setISO, .adjustISO, .clampISO:
            return "camera.aperture"
        case .setShutterSpeed, .setShutterSpeedFraction, .multiplyShutterSpeed, .clampShutterSpeed:
            return "timer"
        case .showToast:
            return "message"
        }
    }

    var titleText: String {
        switch self {
        case .setZoom: return String.actionSetZoom.localized
        case .multiplyZoom: return String.actionMultiplyZoom.localized
        case .clampZoom: return String.actionClampZoom.localized
        case .setExposureBias: return String.actionSetExposureBias.localized
        case .addExposureBias: return String.actionAddExposureBias.localized
        case .setFlashMode: return String.actionSetFlashMode.localized
        case .setFlashModeIfAuto: return String.actionSetFlashModeIfAuto.localized
        case .focusOnSubject: return String.actionFocusOnSubject.localized
        case .focusOnRuleOfThirds: return String.actionFocusOnRuleOfThirds.localized
        case .setFilter: return String.actionSetFilter.localized
        case .importFilterFromURL: return String.automationImportFilter.localized
        case .setWhiteBalance: return String.actionSetWhiteBalance.localized
        case .setWhiteBalanceTemperature: return String.actionSetWhiteBalanceTemperature.localized
        case .setWhiteBalanceTint: return String.actionSetWhiteBalanceTint.localized
        case .adjustWhiteBalanceTemperature: return String.actionAdjustWhiteBalanceTemperature.localized
        case .adjustWhiteBalanceTint: return String.actionAdjustWhiteBalanceTint.localized
        case .setISO: return String.actionSetIso.localized
        case .adjustISO: return String.actionAdjustIso.localized
        case .clampISO: return String.actionClampIso.localized
        case .setShutterSpeed: return String.actionSetShutterSpeed.localized
        case .setShutterSpeedFraction: return String.actionSetShutterSpeed.localized
        case .multiplyShutterSpeed: return String.actionMultiplyShutterSpeed.localized
        case .clampShutterSpeed: return String.actionClampShutterSpeed.localized
        case .showToast: return String.actionShowToast.localized
        }
    }

    var detailText: String {
        switch self {
        case let .setZoom(z): return AutomationFormatters.formatZoom(z)
        case let .multiplyZoom(f): return "×\(AutomationFormatters.trimNumber(f))"
        case let .clampZoom(min, max): return "\(AutomationFormatters.trimNumber(min))x - \(AutomationFormatters.trimNumber(max))x"
        case let .setExposureBias(v): return "\(v > 0 ? "+" : "")\(AutomationFormatters.trimNumber(Double(v)))"
        case let .addExposureBias(v): return "\(v > 0 ? "+" : "")\(AutomationFormatters.trimNumber(Double(v)))"
        case let .setFlashMode(m): return AutomationAction.flashModeDisplayName(m)
        case let .setFlashModeIfAuto(m): return AutomationAction.flashModeDisplayName(m)
        case .focusOnSubject: return String.actionDetailFocusOnSubject.localized
        case .focusOnRuleOfThirds: return String.actionDetailFocusOnRuleOfThirds.localized
        case let .setFilter(f): return f.displayName
        case let .importFilterFromURL(url, displayName):
            return displayName ?? URL(string: url)?.lastPathComponent ?? url
        case let .setWhiteBalance(temperature, tint):
            return String(format: String.unitKelvinTint.localized, Int(temperature), Int(tint))
        case let .setWhiteBalanceTemperature(t): return "\(Int(t))K"
        case let .setWhiteBalanceTint(t): return "\(Int(t))"
        case let .adjustWhiteBalanceTemperature(delta): return "\(delta > 0 ? "+" : "")\(Int(delta))K"
        case let .adjustWhiteBalanceTint(delta): return "\(delta > 0 ? "+" : "")\(Int(delta))"
        case let .setISO(iso): return "ISO \(iso)"
        case let .adjustISO(delta): return "\(delta > 0 ? "+" : "")\(delta)"
        case let .clampISO(min, max): return "\(min) - \(max)"
        case let .setShutterSpeed(seconds): return AutomationFormatters.formatShutter(seconds: seconds)
        case let .setShutterSpeedFraction(n, d): return "\(n)/\(d)s"
        case let .multiplyShutterSpeed(factor): return "×\(AutomationFormatters.trimNumber(factor))"
        case let .clampShutterSpeed(min, max): return "\(AutomationFormatters.formatShutter(seconds: min)) - \(AutomationFormatters.formatShutter(seconds: max))"
        case let .showToast(type, message, _): return "\(AutomationAction.toastTypeDisplayName(type)): \(message)"
        }
    }

    var shortSummary: String {
        switch self {
        case let .setZoom(z): return String.summarySetZoom.localized(AutomationFormatters.formatZoom(z))
        case let .multiplyZoom(f): return String.summaryMultiplyZoom.localized(AutomationFormatters.trimNumber(f))
        case .clampZoom: return String.summaryClampZoom.localized
        case let .setExposureBias(v):
            return v == 0 ? String.summaryExposureBias.localized : (v > 0 ? String.summaryIncreaseExposure.localized(AutomationFormatters.trimNumber(Double(v))) : String.summaryDecreaseExposure.localized(AutomationFormatters.trimNumber(Double(-v))))
        case let .addExposureBias(v):
            return v == 0 ? String.summaryExposureBias.localized : (v > 0 ? String.summaryIncreaseExposure.localized(AutomationFormatters.trimNumber(Double(v))) : String.summaryDecreaseExposure.localized(AutomationFormatters.trimNumber(Double(-v))))
        case let .setFlashMode(mode): return String.summaryFlashMode.localized(AutomationAction.flashModeDisplayName(mode))
        case let .setFlashModeIfAuto(mode): return String.summaryFlashMode.localized(AutomationAction.flashModeDisplayName(mode))
        case .focusOnSubject: return String.summaryFocusOnSubject.localized
        case .focusOnRuleOfThirds: return String.summaryFocusOnRuleOfThirds.localized
        case let .setFilter(type): return String.summaryFilter.localized(type.displayName)
        case let .importFilterFromURL(_, displayName):
            return String.automationImportFilter.localized + " \(displayName ?? String.commonCustom.localized)"
        case let .setWhiteBalance(temperature, tint):
            return String(format: String.unitKelvinTint.localized, Int(temperature), Int(tint))
        case let .setWhiteBalanceTemperature(t):
            return String(format: String.summarySetWhiteBalanceTemperature.localized, Int(t))
        case let .setWhiteBalanceTint(t):
            return String(format: String.summarySetWhiteBalanceTint.localized, Int(t))
        case let .adjustWhiteBalanceTemperature(delta):
            return String(format: String.summaryAdjustWhiteBalanceTemperature.localized, delta)
        case let .adjustWhiteBalanceTint(delta):
            return String(format: String.summaryAdjustWhiteBalanceTint.localized, delta)
        case let .setISO(value): return String.summarySetIso.localized("\(value)")
        case let .adjustISO(delta): return delta >= 0 ? String.summaryIncreaseIso.localized("\(delta)") : String.summaryDecreaseIso.localized("\(-delta)")
        case .clampISO: return String.summaryClampIso.localized
        case let .setShutterSpeed(seconds): return String.summarySetShutterSpeed.localized(AutomationFormatters.formatShutter(seconds: seconds))
        case let .setShutterSpeedFraction(n, d): return String.summarySetShutterSpeed.localized("\(n)/\(d)s")
        case let .multiplyShutterSpeed(factor): return String.summaryMultiplyShutterSpeed.localized(AutomationFormatters.trimNumber(factor))
        case .clampShutterSpeed: return String.summaryClampShutterSpeed.localized
        case .showToast(type: _, message: let message, duration: _):
            let shortMessage = message.count > 6 ? String(message.prefix(6)) + "..." : message
            return String.summaryToast.localized(shortMessage)
        }
    }
}

/// Scoped helpers to avoid global redeclarations
private extension AutomationAction {
    static func flashModeDisplayName(_ mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .off: return String.commonOff.localized
        case .on: return String.commonOn.localized
        case .auto: return String.commonAuto.localized
        @unknown default: return String.commonUnknown.localized
        }
    }

    static func toastTypeDisplayName(_ type: ToastType) -> String {
        switch type {
        case .success: return String.toastTypeSuccess.localized
        case .error: return String.toastTypeError.localized
        case .warning: return String.toastTypeWarning.localized
        case .info: return String.toastTypeInfo.localized
        }
    }
}
