import SwiftUI

// MARK: - Permissions guide view
/// Permission guidance view shown on first startup.
struct OnboardingView: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var isAnimating = false
    @State private var showUserAgreement = false
    @State private var showPrivacyPolicy = false

    /// Callback when onboarding completes.
    var onComplete: () -> Void

    /// Permissions that must be requested.
    private let requiredPermissions: [PermissionType] = [.camera, .photoLibrary]

    /// Whether all required permissions are granted.
    private var allPermissionsGranted: Bool {
        requiredPermissions.allSatisfy { permissionManager.status(for: $0).isGranted }
    }

    var body: some View {
        ZStack {
            // Background.
            backgroundView

            // Content.
            VStack(spacing: 0) {
                Spacer()

                // Logo and title.
                headerSection

                Spacer()

                // Bottom action area.
                VStack(spacing: 0) {
                    // Permission list.
                    permissionList
                        .padding(.bottom, 48)

                    // Main button.
                    startButton
                        .padding(.bottom, 24)

                    // Agreements and privacy.
                    agreementView
                        .padding(.bottom, 48)
                }
                .padding(.horizontal, 32)
            }
        }
        .sheet(isPresented: $showUserAgreement) {
            NavigationStack {
                UserAgreementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showUserAgreement = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                                    .font(.system(size: 24))
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showPrivacyPolicy = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                                    .font(.system(size: 24))
                            }
                        }
                    }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }

    // MARK: - background view
    private var backgroundView: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 400
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()
            .opacity(isAnimating ? 1 : 0)
        }
    }

    // MARK: - head area
    private var headerSection: some View {
        VStack {
            Image("Logo")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.white)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .shadow(color: .white.opacity(0.15), radius: 24, x: 0, y: 0)
        }
        .scaleEffect(isAnimating ? 1 : 0.92)
        .opacity(isAnimating ? 1 : 0)
    }

    // MARK: - Permission list
    private var permissionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(requiredPermissions.enumerated()), id: \.element.rawValue) { index, type in
                PermissionRow(
                    type: type,
                    status: permissionManager.status(for: type),
                    onRequest: {
                        permissionManager.request(type)
                    },
                    onOpenSettings: {
                        permissionManager.openAppSettings()
                    }
                )

                if index < requiredPermissions.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 68)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(0.15), value: isAnimating)
    }

    // MARK: - start button
    private var startButton: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            if allPermissionsGranted {
                completeOnboarding()
            } else {
                requestPendingPermissions()
            }
        } label: {
            Text(allPermissionsGranted
                ? String.onboardingComplete.localized
                : String.onboardingGetStarted.localized)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(white: 0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                }
        }
        .buttonStyle(ScaleButtonStyle())
        .opacity(isAnimating ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: isAnimating)
    }

    // MARK: - Protocol view
    private var agreementView: some View {
        let markdownText = "\(String.onboardingAgreePrefix.localized)[\(String.settingsUserAgreement.localized)](yoyo://agreement)\(String.onboardingAgreeAnd.localized)[\(String.settingsPrivacyPolicy.localized)](yoyo://privacy)"

        return Text(.init(markdownText))
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.62))
            .tint(Color.accentColor.opacity(0.95))
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in
                if url.absoluteString == "yoyo://agreement" {
                    showUserAgreement = true
                    return .handled
                } else if url.absoluteString == "yoyo://privacy" {
                    showPrivacyPolicy = true
                    return .handled
                }
                return .discarded
            })
            .opacity(isAnimating ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: isAnimating)
    }

    // MARK: - Actions

    private func requestPendingPermissions() {
        if let pendingPermission = requiredPermissions.first(where: {
            permissionManager.status(for: $0) == .notDetermined
        }) {
            permissionManager.request(pendingPermission)
        } else if allPermissionsGranted {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        permissionManager.completeOnboarding()
        onComplete()
    }
}

// MARK: - permission line
private struct PermissionRow: View {
    let type: PermissionType
    let status: PermissionStatus
    let onRequest: () -> Void
    let onOpenSettings: () -> Void

    private var isGranted: Bool {
        status == .authorized || status == .limited
    }

    private var isDenied: Bool {
        status == .denied || status == .restricted
    }

    var body: some View {
        HStack(spacing: 16) {
            // Permission icon.
            Image(systemName: type.icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(isGranted ? Color.accentColor : .white.opacity(0.8))
                .frame(width: 32, height: 32)

            // Permission name.
            Text(type.displayName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            // Status / action.
            statusView
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var statusView: some View {
        if isGranted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.accentColor)
        } else if isDenied {
            Button(action: onOpenSettings) {
                Text(String.commonSettings.localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15), in: Capsule())
            }
        } else {
            Button(action: onRequest) {
                Text(String.permissionAuthorizeButton.localized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.05))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
            }
        }
    }
}

// MARK: - button style
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView {
        print("Onboarding completed")
    }
    .environmentObject(PermissionManager.shared)
}
