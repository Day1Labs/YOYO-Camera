import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        WebDocumentView(
            path: "privacy-policy",
            title: String.settingsPrivacyPolicy.localized
        )
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
