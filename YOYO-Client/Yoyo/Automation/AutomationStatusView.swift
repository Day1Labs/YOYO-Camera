import Foundation
import SwiftUI

struct AutomationStatusView: View {
    @ObservedObject var automationManager: CameraAutomationManager
    @ObservedObject var settingsState: CameraSettingsState
    @Binding var showHistory: Bool
    @Binding var showSettings: Bool

    private var enabledRules: [AutomationRule] {
        automationManager.automationEngine.rules.filter(\.isEnabled)
    }

    private var enabledCount: Int {
        enabledRules.count
    }

    /// Read directly from settingsState to ensure reactive updates
    private var isAutomationEnabled: Bool {
        settingsState.automationEnabled
    }

    var body: some View {
        HStack(spacing: 4) {
            statusIconView

            if enabledCount > 0 {
                Text("\(enabledCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(textColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(isAutomationEnabled ? 1.0 : 0.6)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            settingsState.automationEnabled.toggle()
        }
    }

    /// Status icon view
    private var statusIconView: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(iconColor)
    }

    /// Icon name
    private var iconName: String {
        if !isAutomationEnabled {
            return "square.stack.3d.up.slash.fill"
        }
        return "square.stack.3d.up.fill"
    }

    /// Icon color
    private var iconColor: Color {
        .white
    }

    /// Text color
    private var textColor: Color {
        .white
    }
}

#Preview {
    let settingsState = CameraSettingsState.shared
    let automationManager = CameraAutomationManager.shared

    return AutomationStatusView(
        automationManager: automationManager,
        settingsState: settingsState,
        showHistory: .constant(false),
        showSettings: .constant(false)
    )
    .background(Color.black)
}
