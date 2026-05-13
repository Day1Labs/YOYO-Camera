import AppIntents
import SwiftUI

/// Quick capture intent used by the Control Widget to launch the app
/// Note: this file must be added to the target membership of both the main app and the widget extension
struct QuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = .init("yoyo_camera", comment: "YOYO camera intent title")
    static var description = IntentDescription(LocalizedStringResource("yoyo_camera_description", comment: "YOYO camera intent description"))

    /// Set to `true` to open the main app when the intent runs
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Once the app launches, the default home screen is the camera, so return success directly
        .result()
    }
}
