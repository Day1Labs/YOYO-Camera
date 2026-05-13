import AuthenticationServices
import SwiftUI

struct UnifiedAuthSheet: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var authManager = AuthManager.shared

    // Keep a strong reference so the object is not released
    @State private var signInCoordinator = AppleSignInCoordinator()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            if authService.isLoggedIn {
                if !authManager.requiresPro {
                    // Login is required only, and the user is already signed in -> succeed
                    Color.clear.onAppear {
                        authManager.handleSuccess()
                    }
                } else if authService.currentUser?.subscriptionStatus == 1 {
                    // The user is signed in and already Pro, so show success or an empty view (it closes automatically in practice)
                    Color.clear.onAppear {
                        authManager.handleSuccess()
                    }
                } else {
                    // The user is signed in but not Pro, and Pro is required -> show the paywall
                    PaywallView()
                }
            } else {
                // The user is not signed in, so trigger sign-in automatically
                Color.clear
                    .onAppear {
                        // Configure the cancel callback so the sheet closes if the user cancels sign-in
                        signInCoordinator.onCancel = {
                            dismiss()
                        }
                        // Trigger with a short delay to ensure the view has finished loading
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            signInCoordinator.startSignIn()
                        }
                    }
            }
        }
        .presentationBackground(.clear)
        // Observe state changes
        .onChange(of: authService.currentUser?.subscriptionStatus) { status in
            // If the user becomes Pro, all requirements are satisfied
            if status == 1 {
                authManager.handleSuccess()
            }
        }
        .onChange(of: authService.isLoggedIn) { loggedIn in
            // If sign-in succeeds
            if loggedIn {
                // If Pro is not required, succeed immediately
                if !authManager.requiresPro {
                    authManager.handleSuccess()
                } else if authService.currentUser?.subscriptionStatus == 1 {
                    // If Pro is required and the user is already Pro (for example after restoring purchases or due to an existing subscription)
                    authManager.handleSuccess()
                }
            }
        }
    }
}
