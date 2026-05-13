import Foundation
import SwiftUI

/// Photo frame type.
enum FrameType: String, CaseIterable, Codable {
    case none
    case polaroid
    case blurred
    case bottomOnly

    var config: FrameConfig {
        switch self {
        case .none:
            return FrameConfig(type: .none, borderWidth: 0, cornerRadius: 0, backgroundColor: .clear)
        case .polaroid:
            return FrameConfig(type: .polaroid, borderWidth: 0.057, cornerRadius: 0, backgroundColor: .white)
        case .blurred:
            return FrameConfig(type: .blurred, borderWidth: 0.057, cornerRadius: 0.02, backgroundColor: .clear)
        case .bottomOnly:
            return FrameConfig(type: .bottomOnly, borderWidth: 0.12, cornerRadius: 0, backgroundColor: .white)
        }
    }
}

/// Simplified photo frame configuration.
struct FrameConfig: Equatable {
    let type: FrameType
    let borderWidth: CGFloat
    let cornerRadius: CGFloat
    let backgroundColor: Color
}

/// Photo frame template.
struct FrameTemplate: Identifiable, Equatable {
    let id: String
    let config: FrameConfig

    init(type: FrameType) {
        id = type.rawValue
        config = type.config
    }

    static let none = FrameTemplate(type: .none)
    static let polaroid = FrameTemplate(type: .polaroid)
    static let blurred = FrameTemplate(type: .blurred)
    static let bottomOnly = FrameTemplate(type: .bottomOnly)

    static let all: [FrameTemplate] = FrameType.allCases.map { FrameTemplate(type: $0) }

    static func template(withId id: String) -> FrameTemplate? {
        FrameType(rawValue: id).map { FrameTemplate(type: $0) }
    }
}
