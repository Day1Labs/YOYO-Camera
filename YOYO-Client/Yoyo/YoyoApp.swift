import FirebaseCore
import SwiftData
import SwiftUI
import UIKit

enum AppConfig {
    static let isDebugMode = false
}

@main
struct YoyoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var permissionManager = PermissionManager.shared
    @StateObject var languageManager = LanguageManager.shared
    @StateObject var authManager = AuthManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PhotoAsset.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if permissionManager.needsOnboarding {
                    OnboardingView {
                        // It will hide automatically after onboarding is completed
                    }
                } else {
                    CameraView()
                        .buttonStyle(.plain)
                        .trackScreen(name: "CameraMain")
                        .onOpenURL { url in
                            handleURL(url: url)
                        }
                }
            }
            .permissionAlert()
            .environmentObject(permissionManager)
            .environmentObject(languageManager)
            .environment(\.locale, languageManager.locale)
            .id(languageManager.uuid)
            .animation(.easeInOut(duration: 0.3), value: permissionManager.needsOnboarding)
            .fullScreenCover(isPresented: $authManager.showAuthSheet) {
                UnifiedAuthSheet()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task {
                        await AuthService.shared.fetchUserProfile()
                    }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private func handleURL(url: URL) {
        // Record the app launch event triggered by a URL
        AnalyticsManager.shared.log(.appOpenURL(host: url.host ?? "none", path: url.path))

        // Handle URL-based launch
        if url.absoluteString.contains("quick-capture") {
            // Open the camera screen directly; it is already the default screen
        }
    }
}
