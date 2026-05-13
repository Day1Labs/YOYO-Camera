import StoreKit
import SwiftUI

struct PaywallView: View {
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) var dismiss

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    /// Grid columns configuration
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ZStack {
            // Background Layer
            backgroundLayer

            // Content Layer
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 36) {
                        Spacer(minLength: 36)

                        // Header
                        headerSection

                        // Features
                        featuresGrid
                    }
                    .padding(.horizontal, 24)
                }

                // Bottom Fixed Section
                bottomActionSection
            }
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button(String.commonOk.localized, role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .onChange(of: authService.currentUser?.subscriptionStatus) { status in
            if status == 1 {
                dismiss()
            }
        }
    }

    // MARK: - Subviews

    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                // Top Light (Gold/Orange)
                Circle()
                    .fill(Color(hex: "FFD700").opacity(0.12))
                    .blur(radius: 120)
                    .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                    .offset(x: -proxy.size.width * 0.3, y: -proxy.size.width * 0.5)

                // Bottom Light (Orange)
                Circle()
                    .fill(Color(hex: "FFA500").opacity(0.08))
                    .blur(radius: 100)
                    .frame(width: proxy.size.width)
                    .offset(x: proxy.size.width * 0.3, y: proxy.size.height * 0.4)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 20) {
            // Minimal Crown Icon
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.bottom, 4)
                .shadow(color: Color(hex: "FFA500").opacity(0.3), radius: 20, x: 0, y: 0)

            VStack(spacing: 12) {
                Text(String.paywallTitle.localized)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(String.paywallSubtitle.localized)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private var featuresGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            FeatureCard(
                icon: "sparkles",
                text: String.paywallFeatureUnlockAiInspiration.localized
            )
            FeatureCard(
                icon: "wand.and.stars",
                text: String.paywallFeatureAiRetouch.localized
            )
            FeatureCard(
                icon: "person.crop.artframe",
                text: String.paywallFeatureAiPortrait.localized
            )
            FeatureCard(
                icon: "star.circle",
                text: String.paywallFeatureMonthlyCredits.localized
            )
        }
    }

    private var bottomActionSection: some View {
        VStack(spacing: 24) {
            // Subscribe Button
            if let product = storeManager.products.first {
                subscribeButton(product: product)
            } else if storeManager.isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(height: 56)
            } else {
                Text(storeManager.errorMessage ?? String.paywallLoadingProducts.localized)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .frame(height: 56)
            }

            // Footer Links
            VStack(spacing: 16) {
                Text(String.paywallAutoRenewalFooter.localized)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 24) {
                    Button(String.paywallRestorePurchases.localized) {
                        restorePurchases()
                    }

                    Link(String.paywallTermsOfUse.localized, destination: URL(string: "https://static.day1-labs.com/yoyo/user-agreement?lang=\(LanguageManager.shared.currentLanguage.webLanguageCode)")!)

                    Link(String.paywallPrivacyPolicy.localized, destination: URL(string: "https://static.day1-labs.com/yoyo/privacy-policy?lang=\(LanguageManager.shared.currentLanguage.webLanguageCode)")!)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(24)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(.black.opacity(0.6))
                .background(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.2),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .padding(.top, -40)
        )
    }

    private func subscribeButton(product: Product) -> some View {
        Button {
            Task {
                do {
                    if try await storeManager.purchase(product) {}
                } catch {
                    // Reuse restore failed title as a fallback or add a new key "paywall_purchase_failed_title"
                    alertTitle = String.paywallRestoreFailedTitle.localized
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        } label: {
            ZStack {
                // Gradient Background
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFC107"), Color(hex: "FF8F00")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "FF8F00").opacity(0.35), radius: 12, x: 0, y: 6)

                // Content
                if storeManager.isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    HStack(spacing: 6) {
                        Text(String.paywallSubscribeButton.localized)
                            .fontWeight(.bold)
                        Text("•")
                            .font(.system(size: 14))
                        Text(product.displayPrice)
                            .fontWeight(.bold)
                        Text("/")
                            .opacity(0.8)
                        Text(String.paywallPeriodMonthly.localized)
                            .opacity(0.8)
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                }
            }
            .frame(height: 56)
        }
        .disabled(storeManager.isLoading)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(10)
                .background(
                    Circle()
                        .fill(.white.opacity(0.1))
                )
                .padding(20)
        }
    }

    private func restorePurchases() {
        Task {
            do {
                try await storeManager.restorePurchases()
                alertTitle = String.paywallRestoreSuccessTitle.localized
                alertMessage = String.paywallRestoreSuccessMessage.localized
            } catch {
                alertTitle = String.paywallRestoreFailedTitle.localized
                alertMessage = error.localizedDescription
            }
            showAlert = true
        }
    }
}

struct FeatureCard: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Helper extension for Hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    PaywallView()
}
