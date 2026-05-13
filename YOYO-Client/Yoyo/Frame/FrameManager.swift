import Foundation
import SwiftUI

/// Border information display options.
struct FrameInfoOptions: Equatable, Codable {
    var showEXIF: Bool = false
    var showAppleIcon: Bool = false
    var showDeviceModel: Bool = false
    var showDate: Bool = false
    var showTime: Bool = false
    var showLocation: Bool = false
    var showCopyright: Bool = false
    var showFestivalWatermark: Bool = false
    var copyrightText: String = ""

    /// Is there any information that needs to be displayed?
    var hasAnyInfo: Bool {
        showEXIF || showAppleIcon || showDeviceModel || showDate || showTime || showLocation || showCopyright || showFestivalWatermark
    }

    /// No information by default.
    static let none = FrameInfoOptions()
}

/// Photo frame manager.
@MainActor
final class FrameManager: ObservableObject {
    static let shared = FrameManager()

    @AppStorage("selectedFrameTemplateId") private var selectedTemplateId: String = "none" {
        didSet {
            updateCurrentTemplate()
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("isFrameOn") var isFrameOn: Bool = true {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showEXIFInfo") private var _showEXIF: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showAppleIcon") private var _showAppleIcon: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showDeviceModel") private var _showDeviceModel: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showDate") private var _showDate: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showTime") private var _showTime: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showLocation") private var _showLocation: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showCopyright") private var _showCopyright: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    @AppStorage("showFestivalWatermark") private var _showFestivalWatermark: Bool = false {
        didSet {
            updateEnabledState()
            objectWillChange.send()
        }
    }

    /// EXIF information display compatible with the old interface.
    var showEXIFInfo: Bool {
        get { _showEXIF }
        set { _showEXIF = newValue }
    }

    /// Apple icon display.
    var showAppleIcon: Bool {
        get { _showAppleIcon }
        set { _showAppleIcon = newValue }
    }

    /// Device model display.
    var showDeviceModel: Bool {
        get { _showDeviceModel }
        set { _showDeviceModel = newValue }
    }

    /// Shooting date display.
    var showDate: Bool {
        get { _showDate }
        set { _showDate = newValue }
    }

    /// Shooting time display.
    var showTime: Bool {
        get { _showTime }
        set { _showTime = newValue }
    }

    /// Shooting location display.
    var showLocation: Bool {
        get { _showLocation }
        set { _showLocation = newValue }
    }

    /// Copyright information display.
    var showCopyright: Bool {
        get { _showCopyright }
        set { _showCopyright = newValue }
    }

    /// Holiday watermark display.
    var showFestivalWatermark: Bool {
        get { _showFestivalWatermark }
        set { _showFestivalWatermark = newValue }
    }

    /// Information display options.
    var infoOptions: FrameInfoOptions {
        FrameInfoOptions(
            showEXIF: _showEXIF,
            showAppleIcon: _showAppleIcon,
            showDeviceModel: _showDeviceModel,
            showDate: _showDate,
            showTime: _showTime,
            showLocation: _showLocation,
            showCopyright: _showCopyright,
            showFestivalWatermark: _showFestivalWatermark,
            copyrightText: _showCopyright ? CameraSettingsState.shared.copyrightText : ""
        )
    }

    /// Currently selected template.
    @Published var currentTemplate: FrameTemplate = .none

    /// Is the photo frame enabled?
    @Published var isEnabled: Bool = false

    /// Photo frame renderer.
    let renderer = FrameRenderer()

    init() {
        // Initialize the current template.
        updateCurrentTemplate()
        updateEnabledState()
    }

    /// Apply template.
    func applyTemplate(_ template: FrameTemplate) {
        currentTemplate = template
        selectedTemplateId = template.id
    }

    /// Apply photo frame to an image.
    func applyFrameToImage(_ image: UIImage, metadata: [String: Any]? = nil) -> UIImage? {
        renderer.renderFrame(to: image, with: currentTemplate, infoOptions: infoOptions, metadata: metadata)
    }

    // MARK: - Private Methods

    private func updateCurrentTemplate() {
        currentTemplate = FrameTemplate.template(withId: selectedTemplateId) ?? .none
    }

    private func updateEnabledState() {
        isEnabled = isFrameOn && (selectedTemplateId != "none" || infoOptions.hasAnyInfo)
    }
}
