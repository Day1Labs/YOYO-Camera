import CoreGraphics
import Foundation

protocol AutomationDisplayRepresentable {
    var iconSystemName: String { get }
    var titleText: String { get }
    var detailText: String { get }
    var shortSummary: String { get }
}

extension AutomationCondition: AutomationDisplayRepresentable {
    var iconSystemName: String {
        switch self {
        case .sceneIs, .sceneIsNot, .sceneIn:
            return "camera.viewfinder"
        case .lightingIs, .lightingIsNot, .lightingInList:
            return "sun.max.fill"
        case .ruleOfThirdsAlignmentBelow, .ruleOfThirdsAlignmentAbove,
             .frameBiasLeft, .frameBiasRight, .frameBiasTop, .frameBiasBottom, .frameBalanced,
             .visualBalanceBelow, .visualBalanceAbove,
             .backgroundIsSimple, .backgroundIsModerate, .backgroundIsComplex,
             .leadingLineStrengthAbove, .hasMainSubject, .subjectTypeIs:
            return "square.grid.3x3"
        case .subjectSizeBelow, .subjectSizeAbove:
            return "arrow.up.left.and.arrow.down.right"
        case .objectCountAbove, .objectCountEquals, .hasObject:
            return "person.2.fill"
        case .motionLevelAbove, .motionLevelBelow:
            return "figure.run"
        case .highlightRatioAbove, .highlightRatioBelow, .isOverexposed:
            return "sun.max.fill"
        case .timeInRange, .timeAfter, .timeBefore:
            return "clock.fill"
        case .weekdayIs, .weekdayIn:
            return "calendar"
        case .dateIs, .nthWeekdayOfMonth:
            return "calendar.badge.clock"
        case .monthIs, .monthIn:
            return "calendar.circle"
        case .nearLocation, .insideRegion, .outsideRegion:
            return "location.fill"
        case .altitudeAbove, .altitudeBelow, .altitudeInRange:
            return "mountain.2.fill"
        case .colorTemperatureIs, .colorTemperatureIsNot:
            return "paintpalette.fill"
        case .colorSaturationAbove, .colorSaturationBelow:
            return "paintbrush.fill"
        case .colorBrightnessAbove, .colorBrightnessBelow:
            return "sun.min.fill"
        case .dominantColorCount, .dominantColorCountAbove, .dominantColorCountBelow:
            return "eyedropper.halffull"
        case .beforeCapture, .afterCapture:
            return "camera.shutter.button.fill"
        }
    }

    var titleText: String {
        switch self {
        case .sceneIs: return String.conditionSceneIs.localized
        case .sceneIsNot: return String.conditionSceneIsNot.localized
        case .sceneIn: return String.conditionSceneIn.localized
        case .lightingIs: return String.conditionLightingIs.localized
        case .lightingIsNot: return String.conditionLightingIsNot.localized
        case .lightingInList: return String.conditionLightingInList.localized
        case .subjectSizeBelow: return String.conditionSubjectSizeBelow.localized
        case .subjectSizeAbove: return String.conditionSubjectSizeAbove.localized
        case .ruleOfThirdsAlignmentBelow: return String.conditionRuleOfThirdsAlignmentBelow.localized
        case .ruleOfThirdsAlignmentAbove: return String.conditionRuleOfThirdsAlignmentAbove.localized
        case .isOverexposed, .frameBiasLeft, .frameBiasRight, .frameBiasTop, .frameBiasBottom, .frameBalanced, .visualBalanceBelow, .visualBalanceAbove, .leadingLineStrengthAbove:
            return String.conditionFrameGeneric.localized
        case .backgroundIsSimple, .backgroundIsModerate, .backgroundIsComplex: return String.conditionBackground.localized
        case .hasMainSubject: return String.conditionSubject.localized
        case .subjectTypeIs: return String.conditionSubjectTypeIs.localized
        case .objectCountAbove: return String.conditionObjectCountAbove.localized
        case .objectCountEquals: return String.conditionObjectCountEquals.localized
        case .hasObject: return String.conditionHasObject.localized
        case .motionLevelAbove: return String.conditionMotionLevelAbove.localized
        case .motionLevelBelow: return String.conditionMotionLevelBelow.localized
        case .highlightRatioAbove: return String.conditionHighlightRatioAbove.localized
        case .highlightRatioBelow: return String.conditionHighlightRatioBelow.localized
        case .timeInRange: return String.conditionTimeInRange.localized
        case .timeAfter: return String.conditionTimeAfter.localized
        case .timeBefore: return String.conditionTimeBefore.localized
        case .weekdayIs: return String.conditionWeekdayIs.localized
        case .weekdayIn: return String.conditionWeekdayIn.localized
        case .dateIs: return String.conditionDateIs.localized
        case .nthWeekdayOfMonth: return String.conditionNthWeekdayOfMonth.localized
        case .monthIs: return String.conditionMonthIs.localized
        case .monthIn: return String.conditionMonthIn.localized
        case .nearLocation: return String.conditionNearLocation.localized
        case .insideRegion: return String.conditionInsideRegion.localized
        case .outsideRegion: return String.conditionOutsideRegion.localized
        case .altitudeAbove: return String.conditionAltitudeAbove.localized
        case .altitudeBelow: return String.conditionAltitudeBelow.localized
        case .altitudeInRange: return String.conditionAltitudeInRange.localized
        case .colorTemperatureIs: return String.conditionColorTemperatureIs.localized
        case .colorTemperatureIsNot: return String.conditionColorTemperatureIsNot.localized
        case .colorSaturationAbove: return String.conditionSaturationAbove.localized
        case .colorSaturationBelow: return String.conditionSaturationBelow.localized
        case .colorBrightnessAbove: return String.conditionBrightnessAbove.localized
        case .colorBrightnessBelow: return String.conditionBrightnessBelow.localized
        case .dominantColorCount: return String.conditionDominantColorCountEquals.localized
        case .dominantColorCountAbove: return String.conditionDominantColorCountAbove.localized
        case .dominantColorCountBelow: return String.conditionDominantColorCountBelow.localized
        case .beforeCapture: return String.conditionBeforeCapture.localized
        case .afterCapture: return String.conditionAfterCapture.localized
        }
    }

    var detailText: String {
        switch self {
        case let .sceneIs(type): return type.rawValue
        case let .sceneIsNot(type): return type.rawValue
        case let .sceneIn(types): return types.map(\.rawValue).joined(separator: ", ")
        case let .lightingIs(l): return l.description
        case let .lightingIsNot(l): return l.description
        case let .lightingInList(l): return l.map(\.description).joined(separator: ", ")
        case let .subjectSizeBelow(s): return "\(s)"
        case let .subjectSizeAbove(s): return "\(s)"
        case .ruleOfThirdsAlignmentBelow: return String.detailNotAligned.localized
        case .ruleOfThirdsAlignmentAbove: return String.detailAligned.localized
        case .frameBiasLeft: return String.detailBiasLeft.localized
        case .frameBiasRight: return String.detailBiasRight.localized
        case .frameBiasTop: return String.detailBiasTop.localized
        case .frameBiasBottom: return String.detailBiasBottom.localized
        case .frameBalanced: return String.detailBalanced.localized
        case .visualBalanceBelow: return String.detailUnbalanced.localized
        case .visualBalanceAbove: return String.detailBalanceGood.localized
        case .leadingLineStrengthAbove: return String.detailStrongLeadingLines.localized
        case .backgroundIsSimple: return String.detailSimple.localized
        case .backgroundIsModerate: return String.detailModerate.localized
        case .backgroundIsComplex: return String.detailComplex.localized
        case .hasMainSubject: return String.detailObvious.localized
        case let .subjectTypeIs(t): return t == .face ? String.detailSubjectFace.localized : String.detailSubjectSalientRegion.localized
        case let .objectCountAbove(c): return "\(c)"
        case let .objectCountEquals(c): return "\(c)"
        case let .hasObject(l): return l
        case let .motionLevelAbove(l): return "\(l)"
        case let .motionLevelBelow(l): return "\(l)"
        case let .highlightRatioAbove(r): return "\(r)"
        case let .highlightRatioBelow(r): return "\(r)"
        case .isOverexposed: return String.detailOverexposed.localized
        case let .timeInRange(sh, sm, eh, em):
            return String(format: "%02d:%02d - %02d:%02d", sh, sm, eh, em)
        case let .timeAfter(h, m):
            return String(format: "%02d:%02d", h, m)
        case let .timeBefore(h, m):
            return String(format: "%02d:%02d", h, m)
        case let .weekdayIs(w): return AutomationFormatters.weekdayName(w)
        case let .weekdayIn(ws): return ws.map { AutomationFormatters.weekdayName($0) }.joined(separator: ", ")
        case let .dateIs(m, d): return "\(m)月\(d)日"
        case let .nthWeekdayOfMonth(m, w, n):
            return String(format: String.summaryNthWeekdayOfMonth.localized, "\(m)", "\(n)", AutomationFormatters.weekdayName(w))
        case let .monthIs(m): return AutomationFormatters.monthName(m)
        case let .monthIn(ms): return ms.map { AutomationFormatters.monthName($0) }.joined(separator: ", ")
        case let .nearLocation(lat, lon, r):
            return String(format: "(%.4f, %.4f) %dm", lat, lon, Int(r))
        case let .insideRegion(lat, lon, r):
            return String(format: "(%.4f, %.4f) %dm", lat, lon, Int(r))
        case let .outsideRegion(lat, lon, r):
            return String(format: "(%.4f, %.4f) %dm", lat, lon, Int(r))
        case let .altitudeAbove(m): return "\(Int(m))m"
        case let .altitudeBelow(m): return "\(Int(m))m"
        case let .altitudeInRange(min, max): return "\(Int(min))m - \(Int(max))m"
        case let .colorTemperatureIs(temp): return temp.displayName
        case let .colorTemperatureIsNot(temp): return temp.displayName
        case let .colorSaturationAbove(threshold): return "\(Int(threshold * 100))%"
        case let .colorSaturationBelow(threshold): return "\(Int(threshold * 100))%"
        case let .colorBrightnessAbove(threshold): return "\(Int(threshold * 100))%"
        case let .colorBrightnessBelow(threshold): return "\(Int(threshold * 100))%"
        case let .dominantColorCount(count): return "\(count) 种"
        case let .dominantColorCountAbove(count): return "\(count) 种"
        case let .dominantColorCountBelow(count): return "\(count) 种"
        case .beforeCapture: return String.detailBeforeCaptureDesc.localized
        case .afterCapture: return String.detailAfterCaptureDesc.localized
        }
    }

    var shortSummary: String {
        switch self {
        case let .sceneIs(type): return String.summarySceneIs.localized(type.rawValue)
        case let .sceneIsNot(type): return String.summarySceneIsNot.localized(type.rawValue)
        case let .sceneIn(types): return String.summarySceneIn.localized(types.map(\.rawValue).joined(separator: ", "))
        case let .lightingIs(l): return String.summaryLightingIs.localized(l.description)
        case let .lightingIsNot(l): return String.summaryLightingIsNot.localized(l.description)
        case let .lightingInList(l): return String.summaryLightingIn.localized(l.map(\.description).joined(separator: ", "))
        case let .subjectSizeBelow(s): return String.summarySubjectSizeBelow.localized("\(s)")
        case let .subjectSizeAbove(s): return String.summarySubjectSizeAbove.localized("\(s)")
        case .ruleOfThirdsAlignmentBelow: return String.summaryRuleOfThirdsAlignmentBelow.localized
        case .ruleOfThirdsAlignmentAbove: return String.summaryRuleOfThirdsAlignmentAbove.localized
        case .frameBiasLeft: return String.summaryFrameBiasLeft.localized
        case .frameBiasRight: return String.summaryFrameBiasRight.localized
        case .frameBiasTop: return String.summaryFrameBiasTop.localized
        case .frameBiasBottom: return String.summaryFrameBiasBottom.localized
        case .frameBalanced: return String.summaryFrameBalanced.localized
        case .visualBalanceBelow: return String.summaryVisualBalanceBelow.localized
        case .visualBalanceAbove: return String.summaryVisualBalanceAbove.localized
        case let .leadingLineStrengthAbove(v): return String.summaryLeadingLineStrengthAbove.localized("\(Int(v * 100))%")
        case .backgroundIsSimple: return String.summaryBackgroundSimple.localized
        case .backgroundIsModerate: return String.summaryBackgroundModerate.localized
        case .backgroundIsComplex: return String.summaryBackgroundComplex.localized
        case .hasMainSubject: return String.summaryHasMainSubject.localized
        case let .subjectTypeIs(t): return String.summarySubjectTypeIs.localized(t == .face ? String.detailSubjectFace.localized : String.detailSubjectSalientRegion.localized)
        case let .objectCountAbove(c): return String.summaryObjectCountAbove.localized("\(c)")
        case let .objectCountEquals(c): return String.summaryObjectCountEquals.localized("\(c)")
        case let .hasObject(l): return String.summaryHasObject.localized(l)
        case let .motionLevelAbove(l): return String.summaryMotionLevelAbove.localized("\(l)")
        case let .motionLevelBelow(l): return String.summaryMotionLevelBelow.localized("\(l)")
        case let .highlightRatioAbove(r): return String.summaryHighlightRatioAbove.localized("\(r)")
        case let .highlightRatioBelow(r): return String.summaryHighlightRatioBelow.localized("\(r)")
        case .isOverexposed: return String.summaryIsOverexposed.localized
        case let .timeInRange(sh, sm, eh, em):
            return String(format: "%02d:%02d-%02d:%02d", sh, sm, eh, em)
        case let .timeAfter(h, m):
            return String(format: ">= %02d:%02d", h, m)
        case let .timeBefore(h, m):
            return String(format: "< %02d:%02d", h, m)
        case let .weekdayIs(w): return String.summaryWeekdayIs.localized(AutomationFormatters.weekdayName(w))
        case let .weekdayIn(ws): return String.summaryWeekdayIn.localized(ws.map { AutomationFormatters.weekdayName($0) }.joined(separator: ", "))
        case let .dateIs(m, d): return String(format: String.summaryDateIs.localized, "\(m)", "\(d)")
        case let .nthWeekdayOfMonth(m, w, n): return String(format: String.summaryNthWeekdayOfMonth.localized, "\(m)", "\(n)", AutomationFormatters.weekdayName(w))
        case let .monthIs(m): return AutomationFormatters.monthName(m)
        case let .monthIn(ms): return String.summaryMonthIn.localized(ms.map { AutomationFormatters.monthName($0) }.joined(separator: ", "))
        case let .nearLocation(lat, lon, r):
            return String(format: String.summaryNearLocation.localized, lat, lon, Int(r))
        case let .insideRegion(lat, lon, r):
            return String(format: String.summaryInsideRegion.localized, lat, lon, Int(r))
        case let .outsideRegion(lat, lon, r):
            return String(format: String.summaryOutsideRegion.localized, lat, lon, Int(r))
        case let .altitudeAbove(m): return String.summaryAltitudeAbove.localized("\(Int(m))")
        case let .altitudeBelow(m): return String.summaryAltitudeBelow.localized("\(Int(m))")
        case let .altitudeInRange(min, max): return String.summaryAltitudeInRange.localized("\(Int(min))", "\(Int(max))")
        case let .colorTemperatureIs(temp): return String.summaryColorTemperatureIs.localized(temp.displayName)
        case let .colorTemperatureIsNot(temp): return String.summaryColorTemperatureIsNot.localized(temp.displayName)
        case let .colorSaturationAbove(threshold): return String.summarySaturationAbove.localized("\(Int(threshold * 100))%")
        case let .colorSaturationBelow(threshold): return String.summarySaturationBelow.localized("\(Int(threshold * 100))%")
        case let .colorBrightnessAbove(threshold): return String.summaryBrightnessAbove.localized("\(Int(threshold * 100))%")
        case let .colorBrightnessBelow(threshold): return String.summaryBrightnessBelow.localized("\(Int(threshold * 100))%")
        case let .dominantColorCount(count): return String.summaryDominantColorCountEquals.localized("\(count)")
        case let .dominantColorCountAbove(count): return String.summaryDominantColorCountAbove.localized("\(count)")
        case let .dominantColorCountBelow(count): return String.summaryDominantColorCountBelow.localized("\(count)")
        case .beforeCapture: return String.summaryBeforeCapture.localized
        case .afterCapture: return String.summaryAfterCapture.localized
        }
    }
}
