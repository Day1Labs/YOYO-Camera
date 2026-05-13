import SwiftUI

private struct IsUIPreviewKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isUIPreview: Bool {
        get { self[IsUIPreviewKey.self] }
        set { self[IsUIPreviewKey.self] = newValue }
    }
}
