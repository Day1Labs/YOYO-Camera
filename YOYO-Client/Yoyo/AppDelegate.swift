import FirebaseCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // Enable developer mode by default in DEBUG builds
        #if DEBUG
            if UserDefaults.standard.object(forKey: "isDeveloperMode") == nil {
                UserDefaults.standard.set(true, forKey: "isDeveloperMode")
            }
        #endif

        // Log the app launch event
        AnalyticsManager.shared.log(.appLaunch(options: launchOptions?.keys.description ?? "none"))

        return true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Handle launches triggered by a shortcut item
        if let shortcutItem = options.shortcutItem {
            ShortcutItemHandler.shared.handleShortcutItem(shortcutItem)
        }

        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func sceneDidBecomeActive(_: UIScene) {
        // Log the event when the app becomes active
        AnalyticsManager.shared.log(.appBecomeActive)
    }

    func windowScene(
        _: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Handle shortcut item taps while the app is already running
        ShortcutItemHandler.shared.handleShortcutItem(shortcutItem)
        completionHandler(true)
    }
}

/// Singleton handler used to pass shortcut item data between the app and the delegate
final class ShortcutItemHandler: ObservableObject {
    static let shared = ShortcutItemHandler()

    // Store the pending mode in a non-`Published` property to avoid issues during view updates
    private var _pendingCaptureMode: CameraCaptureMode?
    private let lock = NSLock()

    private init() {}

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let type = shortcutItem.type.replacingOccurrences(of: bundleIdentifier + ".", with: "")

        // Log the shortcut launch event
        AnalyticsManager.shared.log(.appOpenShortcut(type: type))

        lock.lock()
        defer { lock.unlock() }

        switch type {
        case "video":
            _pendingCaptureMode = .movie
        case "livephoto":
            _pendingCaptureMode = .livePhoto
        case "photo":
            _pendingCaptureMode = .photo
        default:
            _pendingCaptureMode = nil
        }
    }

    /// Retrieve and clear the pending capture mode in a thread-safe way
    func consumeCaptureMode() -> CameraCaptureMode? {
        lock.lock()
        defer { lock.unlock() }
        let mode = _pendingCaptureMode
        _pendingCaptureMode = nil
        return mode
    }

    /// Check whether a pending capture mode exists without clearing it
    func hasPendingCaptureMode() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _pendingCaptureMode != nil
    }
}
