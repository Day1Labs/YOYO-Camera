import AuthenticationServices
import SwiftUI

final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let authService: AuthService
    /// Callback invoked when sign-in fails or is cancelled
    var onCancel: (() -> Void)?

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Delegate

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task {
            await authService.signInWithApple(authorization: authorization)
        }
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        print("❌ Sign in failed or cancelled: \(error.localizedDescription)")
        onCancel?()
    }

    // MARK: - Presentation Context

    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
