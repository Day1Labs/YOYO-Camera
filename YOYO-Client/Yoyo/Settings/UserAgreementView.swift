import SwiftUI

struct UserAgreementView: View {
    var body: some View {
        WebDocumentView(
            path: "user-agreement",
            title: String.settingsUserAgreement.localized
        )
    }
}

#Preview {
    NavigationStack {
        UserAgreementView()
    }
}
