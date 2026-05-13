import Foundation
import SwiftUI

// MARK: - Automation execution history data structure

enum AutomationTriggerType: String, Codable {
    case automatic = "automation_trigger_automatic"
    case manual = "automation_trigger_manual"
    case confirmed = "automation_trigger_confirmed"
    case cancelled = "automation_trigger_cancelled"

    var icon: String {
        switch self {
        case .automatic: return "sparkles"
        case .manual: return "hand.tap.fill"
        case .confirmed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .automatic: return .blue
        case .manual: return .purple
        case .confirmed: return .green
        case .cancelled: return .orange
        }
    }

    var localizedRawValue: String {
        rawValue.localized
    }
}

struct AutomationExecutionHistory: Identifiable, Codable {
    let id: UUID
    let ruleName: String
    let triggerType: AutomationTriggerType
    let executionTime: Date
    let triggeredConditions: [String]
    let executedActions: [String]
    let sceneContext: String
    let duration: TimeInterval

    var rule: AutomationRule? { nil } // Optional: associate with a specific rule
}

// MARK: - New automation history view

struct AutomationHistoryView: View {
    // New parameter: automation execution history
    var executionHistory: [AutomationExecutionHistory] = []
    @Binding var isPresented: Bool
    var onClearHistory: () -> Void
    @State private var expandedIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // dark theme background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if executionHistory.isEmpty {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        historyListView
                    }
                }
            }
            .navigationTitle(String.automationHistoryTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        onClearHistory()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .disabled(executionHistory.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .trackScreen(name: "AutomationHistory")
    }

    // MARK: - empty state view

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.2))

            Text(String.automationHistoryEmpty.localized)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(40)
    }

    // MARK: - history list

    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(executionHistory.enumerated()), id: \.element.id) { index, item in
                    AutomationExecutionCard(
                        execution: item,
                        isExpanded: expandedIndex == index,
                        accentColor: .accentColor
                    ) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            expandedIndex = expandedIndex == index ? nil : index
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - automation execution card component

struct AutomationExecutionCard: View {
    let execution: AutomationExecutionHistory
    let isExpanded: Bool
    let accentColor: Color
    let onTap: () -> Void

    private let cardColor = Color(red: 0.11, green: 0.11, blue: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            // primary content row
            mainContentRow

            // expanded content
            if isExpanded {
                expandedContent
            }
        }
        .background(cardColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onTapGesture(perform: onTap)
    }

    // MARK: - primary content row

    private var mainContentRow: some View {
        HStack(spacing: 12) {
            // status icon
            statusIconView

            // middle content
            VStack(alignment: .leading, spacing: 4) {
                // task name
                Text(execution.ruleName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // scene and time
                HStack(spacing: 8) {
                    Text(execution.sceneContext)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))

                    Text(relativeTimeString(from: execution.executionTime))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            // right-side info
            // expand icon
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(16)
    }

    // MARK: - trigger-type icons

    private var statusIconView: some View {
        ZStack {
            Circle()
                .fill(execution.triggerType.color.opacity(0.15))
                .frame(width: 32, height: 32)

            Image(systemName: execution.triggerType.icon)
                .font(.system(size: 16))
                .foregroundColor(execution.triggerType.color)
        }
    }

    // MARK: - expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.1))

            // execution details
            executionDetailsSection

            // conditions and actions
            if !execution.triggeredConditions.isEmpty || !execution.executedActions.isEmpty {
                conditionsAndActionsSection
            }
        }
        .padding(16)
        .padding(.top, 4)
    }

    // MARK: - execution details

    private var executionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String.automationExecutionDetails.localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text(String(format: "%.2fs", execution.duration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack {
                Text(String.automationTriggerType.localized)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))

                Text(execution.triggerType.localizedRawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(execution.triggerType.color)

                Spacer()
            }
        }
    }

    // MARK: - conditions and actions

    private var conditionsAndActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !execution.triggeredConditions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String.automationTriggerConditions.localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    ForEach(execution.triggeredConditions, id: \.self) { condition in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.green)

                            Text(condition)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }

            if !execution.executedActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String.automationExecutedActions.localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))

                    ForEach(execution.executedActions, id: \.self) { action in
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(accentColor)

                            Text(action)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
    }

    // MARK: - relative time formatting

    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return String.timeJustNow.localized
        } else if seconds < 3600 {
            return String.timeMinutesAgo.localized(seconds / 60)
        } else if seconds < 86400 {
            return String.timeHoursAgo.localized(seconds / 3600)
        } else {
            return String.timeDaysAgo.localized(seconds / 86400)
        }
    }
}

// MARK: - preview

#Preview {
    let mockHistory = [
        AutomationExecutionHistory(
            id: UUID(),
            ruleName: "人像拍摄优化",
            triggerType: .automatic,
            executionTime: Date().addingTimeInterval(-300),
            triggeredConditions: ["场景是人像", "光照昏暗"],
            executedActions: ["设置缩放1.2x", "曝光补偿+0.3", "开启闪光灯"],
            sceneContext: "人像模式",
            duration: 0.85
        ),
        AutomationExecutionHistory(
            id: UUID(),
            ruleName: "风景拍摄设置",
            triggerType: .manual,
            executionTime: Date().addingTimeInterval(-1800),
            triggeredConditions: ["场景是风景"],
            executedActions: ["设置缩放0.7x", "关闭闪光灯"],
            sceneContext: "风景模式",
            duration: 0.45
        ),
        AutomationExecutionHistory(
            id: UUID(),
            ruleName: "低光补光",
            triggerType: .automatic,
            executionTime: Date().addingTimeInterval(-3600),
            triggeredConditions: ["环境过暗"],
            executedActions: ["ISO调整到800", "快门速度1/30s"],
            sceneContext: "室内环境",
            duration: 0.12
        ),
    ]

    AutomationHistoryView(
        executionHistory: mockHistory,
        isPresented: .constant(true),
        onClearHistory: {}
    )
}
