import SwiftUI

/// Message prompt type.
enum ToastType: String, Codable {
    case success
    case error
    case warning
    case info

    /// Icon for this toast type.
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    /// Accent color for the icon.
    var accentColor: Color {
        switch self {
        case .success: return .white
        case .error: return .red
        case .warning: return .orange
        case .info: return .white
        }
    }
}

/// Message prompt model.
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    let duration: TimeInterval
    let customIcon: String? // Custom icon
    init(type: ToastType, message: String, duration: TimeInterval = 3.0, customIcon: String? = nil) {
        self.type = type
        self.message = message
        self.duration = duration
        self.customIcon = customIcon
    }

    /// Get the final icon displayed, preferring the custom icon.
    var displayIcon: String {
        customIcon ?? type.icon
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Message prompt view.
struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.displayIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(toast.type.accentColor.opacity(0.95))
                .frame(width: 18, height: 18)

            Text(toast.message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassCardStyle(cornerRadius: 12)
    }
}

#Preview("Success Toast") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .success, message: "保存成功"))
    }
}

#Preview("Error Toast") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .error, message: "存储空间不足，无法录制视频"))
    }
}

#Preview("Warning Toast") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .warning, message: "设备温度过高，请注意散热"))
    }
}

#Preview("Info Toast") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .info, message: "正在处理中，请稍候..."))
    }
}

#Preview("Custom Icon - Zoom") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .info, message: "缩放: 2.5x", customIcon: "magnifyingglass"))
    }
}

#Preview("Custom Icon - Filter") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .info, message: "滤镜: 复古", customIcon: "camera.filters"))
    }
}

#Preview("Custom Icon - Lock") {
    ZStack {
        Color.black.ignoresSafeArea()
        ToastView(toast: ToastMessage(type: .info, message: "已锁定对焦和曝光", customIcon: "lock.fill"))
    }
}
