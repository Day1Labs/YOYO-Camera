import SwiftUI

// MARK: - Recommended task detail view

struct RecommendedTaskDetailView: View {
    let task: RecommendedAutomationTask
    let engine: AutomationEngine
    let onTaskAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    // Dark theme colors
    private let backgroundColor = Color.black
    private let cardColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // title and description
                        VStack(alignment: .leading, spacing: 12) {
                            Text(task.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            Text(task.description)
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // if section
                        VStack(alignment: .leading, spacing: 16) {
                            Text(String.automationIfTitle.localized)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 20)

                            VStack(spacing: 12) {
                                ForEach(task.conditions) { condition in
                                    ConditionRow(condition: condition, cardColor: cardColor)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // then do section
                        VStack(alignment: .leading, spacing: 16) {
                            Text(String.automationThenTitle.localized)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 20)

                            VStack(spacing: 12) {
                                ForEach(task.actions) { action in
                                    ActionRow(action: action, cardColor: cardColor)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 100)
                    }
                }

                // bottombutton
                VStack {
                    Button(action: {
                        // use this task
                        let rule = task.toAutomationRule()
                        AnalyticsManager.shared.log(.automationRuleAction(action: "use_recommendation"))
                        engine.addRule(rule)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onTaskAdded()
                        dismiss()
                    }) {
                        Text(String.recTaskUseThis.localized)
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(white: 0.9))
                            .cornerRadius(25)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [backgroundColor.opacity(0), backgroundColor]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                )
            }
        }
        .navigationTitle(String.recTaskSelectionTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .trackScreen(name: "AutomationRecommendationDetail")
    }
}

// MARK: - Condition row

struct ConditionRow: View {
    let condition: RecommendedAutomationTask.ConditionDisplay
    let cardColor: Color

    var body: some View {
        HStack(spacing: 16) {
            // icon
            Image(systemName: condition.icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

            // text
            VStack(alignment: .leading, spacing: 4) {
                Text(condition.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Text(condition.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
}

// MARK: - Action row

struct ActionRow: View {
    let action: RecommendedAutomationTask.ActionDisplay
    let cardColor: Color

    var body: some View {
        HStack(spacing: 16) {
            // icon
            Image(systemName: action.icon)
                .font(.system(size: 24))
                .foregroundColor(action.iconColor)
                .frame(width: 48, height: 48)
                .background(action.iconColor.opacity(0.15))
                .cornerRadius(12)

            // text
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Text(action.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(16)
        .background(cardColor)
        .cornerRadius(12)
    }
}
