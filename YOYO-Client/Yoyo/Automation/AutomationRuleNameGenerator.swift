import Foundation

struct AutomationNameContext {
    var sceneType: SceneType?
    var lighting: LightingCondition?
    var filter: FilterIdentifier?
}

/// Automation rule name generator (scene + action summary, falls back to timestamp when information is insufficient)
enum AutomationRuleNameGenerator {
    static func generate(for rule: AutomationRule, context: AutomationNameContext? = nil) -> String {
        // 1) scene/lighting summary(left part)
        let scene = context?.sceneType ?? findScene(from: rule.conditions)
        let lighting = context?.lighting ?? findLighting(from: rule.conditions)
        var leftParts: [String] = []
        if let scene { leftParts.append(sceneLabel(scene)) }
        if let lighting { leftParts.append(lightingLabel(lighting)) }
        // if none exist, try extracting from conditions such as objects or location
        if leftParts.isEmpty {
            if let objectLabel = findObjectLabel(from: rule.conditions) {
                leftParts.append(objectLabel)
            }
        }
        let left = leftParts.joined(separator: " · ")

        // 2) action summary(right part)
        let actionTexts = summarizeActions(rule.actions, context: context)
        let right = actionTexts.prefix(2).joined(separator: "+")

        // 3) combination and length control(<= 20 chars)
        var title: String
        if !left.isEmpty, !right.isEmpty {
            title = "\(left) · \(right)"
        } else if !left.isEmpty {
            title = left
        } else if !right.isEmpty {
            title = right
        } else {
            // 4) fallback: use the rule ID
            return shortIDFallback(rule.id)
        }

        // 5) trim if it is too long
        if title.count > 20 {
            title = String(title.prefix(20))
        }
        return title
    }

    // MARK: - condition extraction

    private static func findScene(from conditions: [AutomationCondition]) -> SceneType? {
        for c in conditions {
            switch c {
            case let .sceneIs(type): return type
            case let .sceneIn(types): return types.first
            default: continue
            }
        }
        return nil
    }

    private static func findLighting(from conditions: [AutomationCondition]) -> LightingCondition? {
        for c in conditions {
            switch c {
            case let .lightingIs(l): return l
            case let .lightingInList(list): return list.first
            default: continue
            }
        }
        return nil
    }

    private static func findObjectLabel(from conditions: [AutomationCondition]) -> String? {
        for c in conditions {
            if case let .hasObject(label) = c {
                return label
            }
        }
        return nil
    }

    // MARK: - copy mapping

    private static func sceneLabel(_ type: SceneType) -> String {
        switch type {
        case .general: return String.sceneGeneral.localized
        case .portrait: return String.scenePortrait.localized
        case .group: return String.sceneGroup.localized
        case .pet: return String.scenePet.localized
        case .wildlife: return String.sceneWildlife.localized
        case .plant: return String.scenePlant.localized
        case .food: return String.sceneFood.localized
        case .sports: return String.sceneSports.localized
        case .vehicle: return String.sceneVehicle.localized
        case .cityscape: return String.sceneCityscape.localized
        case .interior: return String.sceneInterior.localized
        case .stillLife: return String.sceneStillLife.localized
        case .technology: return String.sceneTechnology.localized
        }
    }

    private static func lightingLabel(_ l: LightingCondition) -> String {
        l.description // This enum already has Chinese descriptions; localization can be added later
    }

    // MARK: - action summary

    private static func summarizeActions(_ actions: [AutomationAction], context _: AutomationNameContext?) -> [String] {
        // Directly reuse each action's short summary to stay consistent with the UI
        let texts = actions.map(\.shortSummary)
        // deduplicate while preserving order
        var seen = Set<String>()
        var unique: [String] = []
        for t in texts {
            if !seen.contains(t) {
                seen.insert(t)
                unique.append(t)
            }
        }
        return unique
    }

    // MARK: - formatting

    // Unified formatting is provided by AutomationFormatters

    private static func shortIDFallback(_ shortID: String) -> String {
        "\(String.automationDefaultRuleTitle.localized) \(shortID)"
    }
}
