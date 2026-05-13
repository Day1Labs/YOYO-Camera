import FirebaseAnalytics
import Foundation
import SwiftUI

/// Defines all analytics events with type safety
enum AnalyticsEvent {
    case appLaunch(options: String)
    case appOpenURL(host: String, path: String)
    case appOpenShortcut(type: String)
    case appBecomeActive
    case screenView(screenName: String, screenClass: String)
    case capturePhoto(mode: String, filter: String?)
    case startVideoRecording(filter: String?)
    case endVideoRecording(duration: Double?)

    // Automation related
    case automationToggle(isOn: Bool)
    case automationRuleAction(action: String) // create, update, import_success, share_success
    case automationTriggered(ruleName: String, triggerType: String)

    // Gallery related
    case galleryAction(action: String) // delete_single, batch_delete, favorite, share_start
    case galleryViewOriginal(isOriginal: Bool)

    /// Settings related
    case settingsAction(action: String)

    var name: String {
        switch self {
        case .appLaunch: return "app_launch"
        case .appOpenURL: return "app_open_url"
        case .appOpenShortcut: return "app_open_shortcut"
        case .appBecomeActive: return "app_open_active"
        case .screenView: return AnalyticsEventScreenView
        case .capturePhoto: return "capture_photo"
        case .startVideoRecording: return "video_record_start"
        case .endVideoRecording: return "video_record_end"
        case .automationToggle: return "automation_toggle"
        case .automationRuleAction: return "automation_rule_action"
        case .automationTriggered: return "automation_triggered"
        case .galleryAction: return "gallery_action"
        case .galleryViewOriginal: return "gallery_view_original"
        case .settingsAction: return "settings_action"
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case let .appLaunch(options):
            return ["launch_options": options]
        case let .appOpenURL(host, path):
            return ["url_host": host, "url_path": path]
        case let .appOpenShortcut(type):
            return ["shortcut_type": type]
        case .appBecomeActive:
            return nil
        case let .screenView(name, className):
            return [
                AnalyticsParameterScreenName: name,
                AnalyticsParameterScreenClass: className,
            ]
        case let .capturePhoto(mode, filter):
            var params: [String: Any] = ["mode": mode]
            if let filter {
                params["filter"] = filter
            }
            return params
        case let .startVideoRecording(filter):
            var params: [String: Any] = [:]
            if let filter {
                params["filter"] = filter
            }
            return params
        case let .endVideoRecording(duration):
            var params: [String: Any] = [:]
            if let duration {
                params["duration"] = duration
            }
            return params
        case let .automationToggle(isOn):
            return ["is_on": isOn]
        case let .automationRuleAction(action):
            return ["action": action]
        case let .automationTriggered(name, triggerType):
            return ["rule_name": name, "trigger_type": triggerType]
        case let .galleryAction(action):
            return ["action": action]
        case let .galleryViewOriginal(isOriginal):
            return ["view_mode": isOriginal ? "original" : "filtered"]
        case let .settingsAction(action):
            return ["action": action]
        }
    }
}

/// Centralized analytics manager
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    private let analyticsEnabledKey = "analyticsEnabled"

    /// Whether the user has enabled analytics (enabled by default)
    var isAnalyticsEnabled: Bool {
        get {
            // Default to true, enabled for first-time users
            if UserDefaults.standard.object(forKey: analyticsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: analyticsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: analyticsEnabledKey)
            Analytics.setAnalyticsCollectionEnabled(newValue)
            #if DEBUG
                print("[Analytics] Analytics collection \(newValue ? "enabled" : "disabled")")
            #endif
        }
    }

    private init() {
        // Initialize Firebase Analytics status
        Analytics.setAnalyticsCollectionEnabled(isAnalyticsEnabled)
    }

    /// Log event
    func log(_ event: AnalyticsEvent) {
        guard isAnalyticsEnabled else {
            #if DEBUG
                print("[Analytics] Skipping event (analytics disabled): \(event.name)")
            #endif
            return
        }

        #if DEBUG
            print("[Analytics] Logging event: \(event.name), parameters: \(event.parameters ?? [:])")
        #endif
        Analytics.logEvent(event.name, parameters: event.parameters)
    }

    /// Set user property
    func setUserProperty(_ value: String?, forName name: String) {
        guard isAnalyticsEnabled else { return }
        Analytics.setUserProperty(value, forName: name)
    }

    /// Set user ID
    func setUserID(_ userID: String?) {
        guard isAnalyticsEnabled else { return }
        Analytics.setUserID(userID)
    }
}

// MARK: - SwiftUI Support

struct AnalyticsViewModifier: ViewModifier {
    let screenName: String
    let screenClass: String

    func body(content: Content) -> some View {
        content.onAppear {
            AnalyticsManager.shared.log(.screenView(screenName: screenName, screenClass: screenClass))
        }
    }
}

extension View {
    /// Track a screen view
    func trackScreen(name: String, className: String? = nil) -> some View {
        modifier(AnalyticsViewModifier(screenName: name, screenClass: className ?? name))
    }
}
