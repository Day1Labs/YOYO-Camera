import SwiftUI

// MARK: - Permissions Alert modifier

struct PermissionAlertModifier: ViewModifier {
    @EnvironmentObject var permissionManager: PermissionManager

    func body(content: Content) -> some View {
        content
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { permissionManager.pendingPermissionAlert != nil },
                    set: { if !$0 { permissionManager.dismissPermissionAlert() } }
                )
            ) {
                Button(String.permissionOpenSettings.localized) {
                    permissionManager.openAppSettings()
                }
                Button(String.commonCancel.localized, role: .cancel) {
                    permissionManager.dismissPermissionAlert()
                }
            } message: {
                Text(alertMessage)
            }
    }

    private var alertTitle: String {
        guard let type = permissionManager.pendingPermissionAlert else {
            return String.permissionDeniedTitle.localized
        }
        return type.displayName
    }

    private var alertMessage: String {
        guard let type = permissionManager.pendingPermissionAlert else {
            return ""
        }
        return type.deniedMessage
    }
}

extension View {
    /// Add Permission Denied Alert prompt
    func permissionAlert() -> some View {
        modifier(PermissionAlertModifier())
    }
}
