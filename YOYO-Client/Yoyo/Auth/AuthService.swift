import AuthenticationServices
import Foundation

// MARK: - User Model

struct User: Codable {
    let id: Int
    let appleUserId: String
    let email: String?
    let fullName: String?
    let credits: Int?
    let subscriptionStatus: Int? // 0: free, 1: pro
}

// MARK: - Auth Response

private struct AuthResponse: Codable {
    let user: User
    let token: String
}

private struct UpdateNameResponse: Codable {
    let fullName: String
}

// MARK: - Auth Service

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var currentUser: User?
    @Published private(set) var authToken: String?
    @Published private(set) var isLoading = false

    private let baseURL = "https://yoyo.day1-labs.com"
    private let userCacheKey = "cachedUser"
    private let tokenCacheKey = "cachedToken"
    private let pendingUserInfoKeyPrefix = "pendingUserInfo_"

    private struct PendingUserInfo: Codable {
        let fullName: String?
        let email: String?
    }

    private init() {
        loadCachedUser()
    }

    // MARK: - Public Methods

    func fetchUserProfile() async {
        guard let token = authToken else { return }

        guard let url = URL(string: "\(baseURL)/api/user") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 {
                print("⚠️ Token expired or invalid, signing out...")
                signOut()
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ Fetch user profile failed: \(httpResponse.statusCode)")
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Fetch user profile response: \(responseString)")
            }

            let user = try JSONDecoder().decode(User.self, from: data)

            await MainActor.run {
                self.currentUser = user
                self.cacheUser(user)
                print("✅ User profile updated: \(user.fullName ?? "Unknown")")
            }
        } catch {
            print("❌ Fetch user profile error: \(error)")
        }
    }

    func syncSubscription(originalTransactionId: String) async throws {
        guard let token = authToken else {
            // Check if user is logged in, if not, we can't sync to a user account
            print("⚠️ Cannot sync subscription: User not logged in")
            return
        }

        guard let url = URL(string: "\(baseURL)/api/user/subscribe") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["originalTransactionId": originalTransactionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Sync Subscription Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        struct SubscribeResponse: Codable {
            let subscriptionStatus: Int
            let subscriptionEndDate: String?
            let credits: Int?
        }

        let subResponse = try JSONDecoder().decode(SubscribeResponse.self, from: data)

        await MainActor.run {
            if let currentUser = self.currentUser {
                let updatedUser = User(
                    id: currentUser.id,
                    appleUserId: currentUser.appleUserId,
                    email: currentUser.email,
                    fullName: currentUser.fullName,
                    credits: subResponse.credits ?? currentUser.credits,
                    subscriptionStatus: subResponse.subscriptionStatus
                )
                self.currentUser = updatedUser
                self.cacheUser(updatedUser)
            }
        }
    }

    func signInWithApple(authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("❌ Invalid credential type")
            return
        }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            print("❌ Missing identity token")
            return
        }

        let userIdentifier = credential.user

        // Build the full name
        var fullName: String?
        if let nameComponents = credential.fullName {
            let parts = [nameComponents.familyName, nameComponents.givenName].compactMap { $0 }
            if !parts.isEmpty {
                fullName = parts.joined()
            }
        }

        var email = credential.email

        // If Apple provides the info (usually only on first authorization), cache it locally first
        // This prevents the info from being lost if a network issue blocks backend sync and Apple does not provide it again later
        if fullName != nil || email != nil {
            cachePendingUserInfo(userIdentifier: userIdentifier, fullName: fullName, email: email)
        }

        // If Apple does not provide the info, try reading previously cached values from local storage
        if fullName == nil || email == nil {
            if let cached = getPendingUserInfo(userIdentifier: userIdentifier) {
                fullName = fullName ?? cached.fullName
                email = email ?? cached.email
                print("ℹ️ Using cached pending user info for \(userIdentifier)")
            }
        }

        print("🔵 Sending auth request to server...")
        print("   userIdentifier: \(userIdentifier)")
        print("   fullName: \(fullName ?? "nil")")
        print("   email: \(email ?? "nil")")

        isLoading = true
        defer { isLoading = false }

        do {
            let (user, token) = try await authenticateWithServer(
                identityToken: identityToken,
                userIdentifier: userIdentifier,
                fullName: fullName,
                email: email
            )

            // Clear the pending info after it has been synced to the backend and a token has been obtained
            clearPendingUserInfo(userIdentifier: userIdentifier)

            currentUser = user
            authToken = token
            cacheUser(user)
            cacheToken(token)
            print("✅ User authenticated: \(user)")
        } catch {
            print("❌ Auth error: \(error)")
            // Keep the cache on authentication failure so the next sign-in retry can attempt syncing again
        }
    }

    func signOut() {
        currentUser = nil
        authToken = nil
        clearCachedUser()
    }

    func deleteAccount() async throws {
        guard let token = authToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/api/user") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        // Sign out after successful deletion
        signOut()
        print("✅ Account deleted successfully")
    }

    func updateCredits(_ newCredits: Int) {
        guard var user = currentUser else { return }

        // Create a new `User` instance because it is a struct and its properties are `let`
        user = User(
            id: user.id,
            appleUserId: user.appleUserId,
            email: user.email,
            fullName: user.fullName,
            credits: newCredits,
            subscriptionStatus: user.subscriptionStatus
        )

        currentUser = user
        cacheUser(user)
        print("✅ Credits updated: \(newCredits)")
    }

    func updateName(_ newName: String) async throws {
        guard let token = authToken else {
            throw AuthError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/api/user") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["fullName": newName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        if let responseString = String(data: data, encoding: .utf8) {
            print("✅ Server response: \(responseString)")
        }

        let updateResponse = try JSONDecoder().decode(UpdateNameResponse.self, from: data)
        let newName = updateResponse.fullName

        await MainActor.run {
            if let currentUser = self.currentUser {
                let updatedUser = User(
                    id: currentUser.id,
                    appleUserId: currentUser.appleUserId,
                    email: currentUser.email,
                    fullName: newName,
                    credits: currentUser.credits,
                    subscriptionStatus: currentUser.subscriptionStatus
                )
                self.currentUser = updatedUser
                self.cacheUser(updatedUser)
            }
        }

        print("✅ Name updated: \(newName)")
    }

    // MARK: - Debug

    func debugSetProStatus(isPro: Bool) {
        guard let user = currentUser else { return }

        let updatedUser = User(
            id: user.id,
            appleUserId: user.appleUserId,
            email: user.email,
            fullName: user.fullName,
            credits: user.credits,
            subscriptionStatus: isPro ? 1 : 0
        )

        currentUser = updatedUser
        // Note: We intentionally do not cache this debug state so it resets on relaunch
        print("🔧 Debug: Pro status set to \(isPro)")
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    // MARK: - Private Methods

    private func authenticateWithServer(
        identityToken: String,
        userIdentifier: String,
        fullName: String?,
        email: String?
    ) async throws -> (User, String) {
        guard let url = URL(string: "\(baseURL)/api/auth/apple") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "identityToken": identityToken,
            "userIdentifier": userIdentifier,
        ]
        if let fullName { body["fullName"] = fullName }
        if let email { body["email"] = email }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw AuthError.serverError(httpResponse.statusCode)
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        return (authResponse.user, authResponse.token)
    }

    // MARK: - Cache

    private func cacheUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userCacheKey)
        }
    }

    private func cacheToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenCacheKey)
    }

    private func loadCachedUser() {
        if let data = UserDefaults.standard.data(forKey: userCacheKey),
           let user = try? JSONDecoder().decode(User.self, from: data)
        {
            currentUser = user
        }
        if let token = UserDefaults.standard.string(forKey: tokenCacheKey) {
            authToken = token
        }
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: userCacheKey)
        UserDefaults.standard.removeObject(forKey: tokenCacheKey)
    }

    private func cachePendingUserInfo(userIdentifier: String, fullName: String?, email: String?) {
        let info = PendingUserInfo(fullName: fullName, email: email)
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: pendingUserInfoKeyPrefix + userIdentifier)
        }
    }

    private func getPendingUserInfo(userIdentifier: String) -> PendingUserInfo? {
        guard let data = UserDefaults.standard.data(forKey: pendingUserInfoKeyPrefix + userIdentifier),
              let info = try? JSONDecoder().decode(PendingUserInfo.self, from: data)
        else {
            return nil
        }
        return info
    }

    private func clearPendingUserInfo(userIdentifier: String) {
        UserDefaults.standard.removeObject(forKey: pendingUserInfoKeyPrefix + userIdentifier)
    }
}

// MARK: - Auth Error

enum AuthError: Error {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case notAuthenticated
}
