import AppIntents
import SwiftUI
import WidgetKit

struct YoyoControlWidgetControl: ControlWidget {
    static let kind: String = "com.day1-labs.yoyo.control-widget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: QuickCaptureIntent()) {
                Label(NSLocalizedString("yoyo_camera", comment: "YOYO camera widget label"), systemImage: "camera")
            }
        }
        .displayName(LocalizedStringResource("yoyo_camera", comment: "YOYO camera widget display name"))
        .description(LocalizedStringResource("yoyo_camera_description", comment: "YOYO camera widget description"))
    }
}
