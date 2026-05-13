import SwiftUI

/// Optimized AI Automation history overlay
struct AutomationHistoryOverlay: View {
    let automationManager: CameraAutomationManager
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // transparent overlay
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPresented = false
                    }
                }

            // Automation history view
            VStack {
                Spacer()
                AutomationHistoryView(
                    executionHistory: automationManager.executionHistory,
                    isPresented: $isPresented,
                    onClearHistory: {
                        automationManager.executionHistory.removeAll()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
