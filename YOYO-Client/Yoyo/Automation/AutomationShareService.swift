import Foundation

// MARK: - Share Response

private struct ShareResponse: Codable {
    let code: String
}

private struct GetSharedRuleResponse: Codable {
    let ruleJson: String
}

/// DTO for sharing that strictly excludes local-only fields like shareCode
private struct SharedAutomationRule: Codable {
    let id: String
    let name: String
    let conditions: [AutomationCondition]
    let actions: [AutomationAction]
    let conditionLogic: ConditionLogic
    let priority: Int
    let isEnabled: Bool
    let requireConfirmation: Bool?
    let createdAt: Date
    let executionInterval: TimeInterval

    init(from rule: AutomationRule) {
        id = rule.id
        name = rule.name
        conditions = rule.conditions
        actions = rule.actions
        conditionLogic = rule.conditionLogic
        priority = rule.priority
        isEnabled = rule.isEnabled
        requireConfirmation = rule.requireConfirmation
        createdAt = rule.createdAt
        executionInterval = rule.executionInterval
    }
}

// MARK: - Share Error

enum ShareError: Error, LocalizedError {
    case notLoggedIn
    case invalidResponse
    case serverError(Int)
    case networkError(Error)
    case decodingError
    case codeNotFound

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return String.shareErrorNotLoggedIn.localized
        case .invalidResponse:
            return String.shareErrorInvalidResponse.localized
        case let .serverError(code):
            return String.shareErrorServer.localized(code)
        case .networkError:
            return String.shareErrorNetwork.localized
        case .decodingError:
            return String.shareErrorDecoding.localized
        case .codeNotFound:
            return String.shareErrorCodeNotFound.localized
        }
    }
}

// MARK: - Automation Share Service

@MainActor
final class AutomationShareService {
    static let shared = AutomationShareService()

    private let baseURL = "https://yoyo.day1-labs.com"

    private init() {}

    // MARK: - Share Rule

    /// Share an automation rule and return a 6-digit share code
    func shareRule(_ rule: AutomationRule) async throws -> String {
        guard let token = AuthService.shared.authToken else {
            throw ShareError.notLoggedIn
        }

        guard let url = URL(string: "\(baseURL)/api/automation/share") else {
            throw ShareError.invalidResponse
        }

        // Use DTO to ensure shareCode is strictly excluded from JSON
        let sharedRule = SharedAutomationRule(from: rule)

        // Encode rule to JSON
        let encoder = JSONEncoder()
        let ruleData = try encoder.encode(sharedRule)
        guard let ruleJson = String(data: ruleData, encoding: .utf8) else {
            throw ShareError.decodingError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "ruleJson": ruleJson,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ShareError.serverError(httpResponse.statusCode)
        }

        let shareResponse = try JSONDecoder().decode(ShareResponse.self, from: data)
        return shareResponse.code
    }

    // MARK: - Get Shared Rule

    /// Get an automation rule by share code
    func getSharedRule(code: String) async throws -> AutomationRule {
        let cleanCode = code.trimmingCharacters(in: .whitespaces).uppercased()

        guard cleanCode.count == 6 else {
            throw ShareError.codeNotFound
        }

        guard let url = URL(string: "\(baseURL)/api/automation/share/\(cleanCode)") else {
            throw ShareError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw ShareError.codeNotFound
        }

        guard httpResponse.statusCode == 200 else {
            throw ShareError.serverError(httpResponse.statusCode)
        }

        let getResponse = try JSONDecoder().decode(GetSharedRuleResponse.self, from: data)

        guard let ruleData = getResponse.ruleJson.data(using: .utf8) else {
            throw ShareError.decodingError
        }

        var rule = try JSONDecoder().decode(AutomationRule.self, from: ruleData)
        // Generate a new ID, avoid conflicts with local rules
        rule.id = AutomationRule.generateUniqueShortID()
        rule.shareCode = nil // clear the original share code
        rule.createdAt = Date()

        return rule
    }
}
