import Combine
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var showAuthSheet = false

    /// Default to true (Pro required)
    var requiresPro: Bool = true

    private var onSuccessAction: (() -> Void)?

    private init() {}

    /// Unified check method
    func checkAuth(requiresPro: Bool = true, onSuccess: @escaping () -> Void) {
        self.requiresPro = requiresPro
        let authService = AuthService.shared

        if authService.isLoggedIn {
            if !requiresPro {
                // If only login is required, and user is logged in
                onSuccess()
            } else if authService.currentUser?.subscriptionStatus == 1 {
                // If Pro is required, and user is Pro
                onSuccess()
            } else {
                // Logged in but not Pro (and Pro is required) -> Show Paywall
                onSuccessAction = onSuccess
                showAuthSheet = true
            }
        } else {
            // Not logged in -> Show Login
            onSuccessAction = onSuccess
            showAuthSheet = true
        }
    }

    /// Legacy support (points to new method)
    func checkProAccess(onSuccess: @escaping () -> Void) {
        checkAuth(requiresPro: true, onSuccess: onSuccess)
    }

    func handleSuccess() {
        showAuthSheet = false
        onSuccessAction?()
        onSuccessAction = nil
    }
}
