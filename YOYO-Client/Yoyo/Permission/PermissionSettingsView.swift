import PhotosUI
import SwiftUI

// MARK: - Permission setting view

struct PermissionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        ZStack {
            Color(white: 0.04).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Permission status list
                    permissionsList

                    // Album restricted access tips
                    if permissionManager.isPhotoLibraryLimited {
                        limitedPhotoAccessCard
                    }

                    // Description text
                    footerText
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle(String.permissionSettingsTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .trackScreen(name: "PermissionSettings")
    }

    // MARK: - Permission list

    private var permissionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String.permissionSettingsStatus.localized)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(paddingValue: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(PermissionType.allCases.enumerated()), id: \.element) { index, type in
                        PermissionStatusRow(permissionType: type)

                        if index < PermissionType.allCases.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Album restricted access card

    private var limitedPhotoAccessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String.permissionLimitedAccessTitle.localized)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(paddingValue: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String.permissionLimitedAccessMessage.localized)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }

                    Button(action: {
                        presentLimitedLibraryPicker()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text(String.permissionSelectMorePhotos.localized)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Bottom description

    private var footerText: some View {
        Text(String.permissionSettingsFooter.localized)
            .font(.system(size: 12))
            .foregroundStyle(.gray.opacity(0.7))
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    // MARK: - Open restricted album selector

    private func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController
        else {
            return
        }

        // Find the top-level ViewController
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topController)
    }
}

// MARK: - permission status line

private struct PermissionStatusRow: View {
    let permissionType: PermissionType
    @EnvironmentObject var permissionManager: PermissionManager

    private var status: PermissionStatus {
        permissionManager.status(for: permissionType)
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 12) {
                // icon
                Image(systemName: permissionType.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(8)

                // title
                Text(permissionType.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                Spacer()

                // status label
                statusBadge

                // arrow icon
                Image(systemName: status == .notDetermined ? "plus.circle" : "arrow.up.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleTap() {
        if status == .notDetermined {
            permissionManager.request(permissionType)
        } else {
            permissionManager.openAppSettings()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(6)
    }

    private var statusColor: Color {
        switch status {
        case .authorized:
            return .green
        case .limited:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .authorized:
            return String.permissionStatusAuthorized.localized
        case .limited:
            return String.permissionStatusLimited.localized
        case .denied:
            return String.permissionStatusDenied.localized
        case .restricted:
            return String.permissionStatusRestricted.localized
        case .notDetermined:
            return String.permissionStatusNotDetermined.localized
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PermissionSettingsView()
            .environmentObject(PermissionManager.shared)
    }
}
