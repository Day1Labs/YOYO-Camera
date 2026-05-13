import Foundation
import StoreKit

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // TODO: Replace with your actual product IDs from App Store Connect
    private let productIDs = ["yoyo.pro.subscription.auto.renewable.monthly"]
    private let lastTransactionIdKey = "lastKnownOriginalTransactionId"

    var updateListenerTask: Task<Void, Error>?

    /// Detects if the app is running in Sandbox environment
    private var isSandbox: Bool {
        #if DEBUG
            return true
        #else
            // In production, we can check the transaction environment
            // For now, we assume production when not in DEBUG
            return false
        #endif
    }

    private init() {
        // Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()

        Task {
            await requestProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func requestProducts() async {
        print("🛒 StoreKit Environment: \(isSandbox ? "Sandbox" : "Production")")
        print("🛒 Requesting products: \(productIDs)")
        print("🛒 Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        do {
            products = try await Product.products(for: productIDs)
            print("✅ Successfully fetched \(products.count) products")
            for product in products {
                print("   - \(product.displayName): \(product.displayPrice) (\(product.id))")
            }
            if products.isEmpty {
                print("⚠️ No products returned. Please check App Store Connect configuration or StoreKit setup.")
            }
        } catch {
            print("❌ Failed to fetch products: \(error)")
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        print("🛍️ Initiating purchase for product: \(product.id)")
        let result = try await product.purchase()

        switch result {
        case let .success(verification):
            print("🛍️ Purchase result: .success")
            // Check whether the transaction is verified. If it isn't,
            // this function rethrows the verification error.
            let transaction = try checkVerified(verification)

            print("""
            🛍️ Transaction Details:
            - Product ID: \(transaction.productID)
            - Transaction ID: \(transaction.id)
            - Original ID: \(transaction.originalID)
            - Purchase Date: \(transaction.purchaseDate)
            - Expiration Date: \(transaction.expirationDate?.description ?? "N/A")
            - Revocation Date: \(transaction.revocationDate?.description ?? "N/A")
            - Is Upgraded: \(transaction.isUpgraded)
            """)

            // Sync with Server
            await syncWithServer(transaction: transaction)

            // The transaction is verified. Deliver content to the user.
            await updateCustomerProductStatus(syncLatestIfNoEntitlement: false)

            // Always finish a transaction.
            await transaction.finish()
            return true

        case .userCancelled:
            print("🛍️ Purchase result: .userCancelled")
            return false

        case .pending:
            print("🛍️ Purchase result: .pending")
            return false

        default:
            print("🛍️ Purchase result: unknown default case")
            return false
        }
    }

    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }

        try await AppStore.sync()
        await updateCustomerProductStatus()

        // Find valid entitlement to sync with server
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                await syncWithServer(transaction: transaction)
                return // Syncing one valid subscription is enough
            }
        }

        // If we reach here, no active subscription was found in entitlements
        throw StoreError.noPurchasesToRestore
    }

    func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Deliver content to the user.
                    await self.updateCustomerProductStatus(syncLatestIfNoEntitlement: false)

                    // Sync with Server
                    await self.syncWithServer(transaction: transaction)

                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }

    @MainActor
    func updateCustomerProductStatus(syncLatestIfNoEntitlement: Bool = true) async {
        var purchasedIDs = Set<String>()

        // Iterate through all of the user's purchased products.
        for await result in Transaction.currentEntitlements {
            do {
                // Check whether the transaction is verified. If it isn't,
                // this function rethrows the verification error.
                let transaction = try checkVerified(result)

                // Check the `productType` of the transaction and
                // check if the transaction is revoked.
                if transaction.revocationDate == nil {
                    purchasedIDs.insert(transaction.productID)
                }
            } catch {
                print("Failed to verify transaction in entitlements")
            }
        }

        purchasedProductIDs = purchasedIDs

        // If no active entitlement found locally, we should check the latest transaction history
        // from App Store to sync the correct status (Expired/Revoked) to server.
        // This handles the case where user deleted the app (lost UserDefaults) and reinstalled it after expiration.
        if purchasedIDs.isEmpty, syncLatestIfNoEntitlement {
            print("🔄 No active entitlement found. Checking latest transaction history...")
            for productID in productIDs {
                if let result = await Transaction.latest(for: productID) {
                    // Even if verification fails or it's expired, we want the ID to sync status.
                    // However, we typically only trust verified transactions.
                    if let transaction = try? checkVerified(result) {
                        print("Found historical transaction for \(productID). Syncing...")
                        await syncWithServer(transaction: transaction)
                        // Once we find one valid historical transaction for our sub group, that's enough to establish status
                        break
                    }
                }
            }
        }
    }

    nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            // StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case let .verified(safe):
            // The result is verified. Return the unwrapped value.
            return safe
        }
    }

    // MARK: - Server Sync

    private func syncWithServer(transaction: Transaction) async {
        // Use StoreKit 2 originalTransactionID for server-side validation using App Store Server API
        let originalTransactionId = String(transaction.originalID)

        // Cache the ID for future expiration checks
        UserDefaults.standard.set(originalTransactionId, forKey: lastTransactionIdKey)

        await syncWithServer(originalTransactionId: originalTransactionId)
    }

    private func syncWithServer(originalTransactionId: String) async {
        do {
            try await AuthService.shared.syncSubscription(originalTransactionId: originalTransactionId)
            print("✅ Subscription synced with server (ID: \(originalTransactionId))")
        } catch {
            print("❌ Failed to sync subscription: \(error)")
        }
    }
}

enum StoreError: Error, LocalizedError {
    case failedVerification
    case noPurchasesToRestore

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed."
        case .noPurchasesToRestore:
            return "No active subscriptions found to restore."
        }
    }
}
