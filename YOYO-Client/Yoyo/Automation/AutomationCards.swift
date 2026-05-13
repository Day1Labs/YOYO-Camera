import AVFoundation
import SwiftUI

struct AutomationCardHeader: View {
    let title: String
    let subtitle: String?
    let titleColor: Color
    let subtitleColor: Color
    let titleFont: Font
    let subtitleFont: Font
    let alignment: VerticalAlignment
    let leading: AnyView?
    let trailing: AnyView?

    init(title: String,
         subtitle: String? = nil,
         titleColor: Color = .white,
         subtitleColor: Color = .gray,
         titleFont: Font = .system(size: 17, weight: .bold),
         subtitleFont: Font = .system(size: 14),
         alignment: VerticalAlignment = .top,
         leading: AnyView? = nil,
         trailing: AnyView? = nil)
    {
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.alignment = alignment
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            if let leading {
                leading
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(titleFont)
                    .foregroundColor(titleColor)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundColor(subtitleColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if let trailing {
                trailing
            }
        }
    }
}

/// Recommended task card
struct RecommendedAutomationRuleCard: View {
    let task: RecommendedAutomationTask
    let cardColor: Color

    var body: some View {
        GlassCard(cardColor: cardColor) {
            AutomationCardHeader(
                title: task.title,
                subtitle: task.description,
                titleColor: .white,
                subtitleColor: .gray,
                alignment: .center,
                leading: AnyView(
                    Image(systemName: task.icon)
                        .font(.system(size: 24))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 40, height: 40)
                ),
                trailing: AnyView(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.5))
                        .frame(width: 40, height: 40)
                )
            )
        }
    }
}

/// Rule card (with toggle)
struct AutomationRuleCard: View {
    let rule: AutomationRule
    let automationManager: CameraAutomationManager
    let cardColor: Color
    let accentColor: Color

    @State private var isEnabled: Bool
    @State private var requireConfirmation: Bool

    // Share states
    @State private var showingShareSheet = false
    @State private var tempShareCode: String?
    @State private var isSharing = false
    @State private var shareError: String?

    init(rule: AutomationRule, automationManager: CameraAutomationManager, cardColor: Color, accentColor: Color) {
        self.rule = rule
        self.automationManager = automationManager
        self.cardColor = cardColor
        self.accentColor = accentColor
        _isEnabled = State(initialValue: rule.isEnabled)
        _requireConfirmation = State(initialValue: rule.requireConfirmation ?? true)
    }

    var body: some View {
        GlassCard(cardColor: cardColor) {
            VStack(alignment: .leading, spacing: -8) {
                AutomationCardHeader(
                    title: rule.name,
                    titleColor: isEnabled ? .white : .gray,
                    subtitleColor: .gray,
                    titleFont: .system(size: 16, weight: .bold),
                    alignment: .center,
                    trailing: AnyView(
                        Menu {
                            Button {
                                Task {
                                    let success = await automationManager.executeRuleOnce(rule)
                                    if success {
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    } else {
                                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                                    }
                                }
                            } label: {
                                Label(String.automationExecuteOnce.localized, systemImage: "play.fill")
                            }

                            Toggle(isOn: Binding(
                                get: { requireConfirmation },
                                set: { newValue in
                                    requireConfirmation = newValue
                                    var updatedRule = rule
                                    updatedRule.requireConfirmation = newValue
                                    automationManager.automationEngine.updateRule(updatedRule)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            )) {
                                Label(String.automationRequireConfirmation.localized, systemImage: "checkmark.shield")
                            }

                            // Quick Task Toggle
                            Button {
                                QuickTaskManager.shared.toggleQuickTask(ruleId: rule.id)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                if QuickTaskManager.shared.isInQuickTasks(ruleId: rule.id) {
                                    Label(String.quickTaskRemove.localized, systemImage: "bolt.slash")
                                } else {
                                    Label(String.quickTaskAdd.localized, systemImage: "bolt")
                                }
                            }

                            Divider()

                            // Share Section
                            if let code = rule.shareCode {
                                Button {
                                    UIPasteboard.general.string = code
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } label: {
                                    Label(String.automationCopyShareCode.localized.replacingOccurrences(of: "%@", with: code), systemImage: "clipboard")
                                        .lineLimit(1)
                                }
                            }

                            Button {
                                handleShareTap()
                            } label: {
                                if isSharing {
                                    Label(String.automationSharing.localized, systemImage: "arrow.triangle.2.circlepath")
                                } else {
                                    Label(rule.shareCode == nil ? String.automationShareTask.localized : String.automationReshare.localized, systemImage: "square.and.arrow.up")
                                }
                            }
                            .disabled(isSharing)

                            Button {
                                var clonedRule = rule
                                clonedRule.id = AutomationRule.generateUniqueShortID()
                                let existingNames = automationManager.automationEngine.rules.map(\.name)
                                clonedRule.name = NamingUtils.generateUniqueName(for: rule.name, among: existingNames)
                                clonedRule.shareCode = nil // Reset share code for clone
                                automationManager.automationEngine.addRule(clonedRule, after: rule.id)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label(String.automationCloneTask.localized, systemImage: "doc.on.doc")
                            }

                            Button(role: .destructive) {
                                automationManager.automationEngine.deleteRule(rule.id)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label(String.automationDeleteTask.localized, systemImage: "trash")
                            }
                        } label: {
                            if isSharing {
                                ProgressView()
                                    .tint(.gray)
                                    .frame(width: 44, height: 44)
                            } else {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    )
                ).offset(y: -14)

                // condition -> actionflow
                HStack(alignment: .center, spacing: 12) {
                    let (cShow, aShow) = calculateDisplayCounts(cCount: rule.conditions.count, aCount: rule.actions.count)

                    // left side: condition icon group
                    HStack(spacing: 8) {
                        // ifnocondition, displaymanual triggericon
                        if rule.conditions.isEmpty {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 18))
                                .foregroundColor(isEnabled ? .white.opacity(0.8) : .gray)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            // displaycalculatecomputed count
                            ForEach(Array(rule.conditions.prefix(cShow).enumerated()), id: \.offset) { _, condition in
                                Image(systemName: condition.iconSystemName)
                                    .font(.system(size: 18))
                                    .foregroundColor(isEnabled ? .white.opacity(0.8) : .gray)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            // ifneedtruncate
                            if rule.conditions.count > cShow {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18))
                                    .foregroundColor(isEnabled ? .white.opacity(0.8) : .gray)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }

                    // arrow
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16))
                        .foregroundColor(isEnabled ? .white.opacity(0.6) : .gray.opacity(0.6))

                    // right side: action icon group
                    HStack(spacing: 8) {
                        // ifnoaction, displayquestion-mark icon
                        if rule.actions.isEmpty {
                            Image(systemName: "questionmark")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                        } else {
                            // displaycalculatecomputed count
                            ForEach(Array(rule.actions.prefix(aShow).enumerated()), id: \.offset) { _, action in
                                Image(systemName: action.iconSystemName)
                                    .font(.system(size: 18))
                                    .foregroundColor(isEnabled ? .white.opacity(0.8) : .gray)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            // ifneedtruncate
                            if rule.actions.count > aShow {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18))
                                    .foregroundColor(isEnabled ? .white.opacity(0.8) : .gray)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }

                    Spacer()

                    // toggle
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .tint(accentColor)
                        .onChange(of: isEnabled) { _, newValue in
                            var updatedRule = rule
                            updatedRule.isEnabled = newValue
                            automationManager.automationEngine.updateRule(updatedRule)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.6)
        .contentShape(Rectangle())
        .fullScreenCover(isPresented: $showingShareSheet) {
            if let code = tempShareCode {
                AutomationShareResultView(
                    code: code,
                    onCopy: {
                        UIPasteboard.general.string = code
                        withAnimation { showingShareSheet = false }
                    },
                    onDismiss: {
                        withAnimation { showingShareSheet = false }
                    }
                )
                .presentationBackground(.clear)
            }
        }
        .alert(String.automationShareFailed.localized, isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button(String.automationConfirmButton.localized, role: .cancel) {}
        } message: {
            if let error = shareError {
                Text(error)
            }
        }
    }

    private func handleShareTap() {
        AuthManager.shared.checkAuth(requiresPro: false) {
            performShare()
        }
    }

    private func performShare() {
        isSharing = true
        Task {
            do {
                let code = try await AutomationShareService.shared.shareRule(rule)
                tempShareCode = code

                // persist and save
                var updatedRule = rule
                updatedRule.shareCode = code
                automationManager.automationEngine.updateRule(updatedRule)

                withAnimation {
                    showingShareSheet = true
                }
            } catch {
                shareError = error.localizedDescription
            }
            isSharing = false
        }
    }

    // Return the corresponding icon for a condition
    // Icon mapping is provided by AutomationCondition.iconSystemName/AutomationAction.iconSystemName

    // Return the corresponding icon for an action
    // Icon mapping is provided by AutomationCondition.iconSystemName/AutomationAction.iconSystemName

    /// Calculate the number of icons to display
    private func calculateDisplayCounts(cCount: Int, aCount: Int) -> (cShow: Int, aShow: Int) {
        let maxIcons = 5

        // If the total count does not exceed the limit, display all icons
        if cCount + aCount <= maxIcons {
            return (cCount, aCount)
        }

        var best = (0, 0)
        var maxScore = -Double.infinity

        // ensure at least 1 is displayed(if it exists)
        let minC = cCount > 0 ? 1 : 0
        let minA = aCount > 0 ? 1 : 0

        // iterate through all possible combinations
        for i in minC ... min(cCount, maxIcons) {
            for j in minA ... min(aCount, maxIcons) {
                // Calculate the occupied slots (including ellipsis)
                let slotsC = i + (i < cCount ? 1 : 0)
                let slotsA = j + (j < aCount ? 1 : 0)

                if slotsC + slotsA <= maxIcons {
                    // scoring system:
                    // 1. Total icon count (weight 1000) - more is better
                    // 2. ellipsiscount (weight -100) - fewer is better ("avoid ellipsis whenever possible")
                    // 3. countdifference (weight -1) - more balanced is better

                    let sum = i + j
                    let ellipses = (i < cCount ? 1 : 0) + (j < aCount ? 1 : 0)
                    let diff = abs(i - j)

                    let score = Double(sum) * 1000.0 - Double(ellipses) * 100.0 - Double(diff)

                    if score > maxScore {
                        maxScore = score
                        best = (i, j)
                    } else if score == maxScore {
                        // tie-break handling: prioritizedisplaymorecondition
                        if i > best.0 {
                            best = (i, j)
                        }
                    }
                }
            }
        }

        return best
    }
}

// MARK: - Previews

#Preview("任务卡片") {
    VStack(spacing: 16) {
        RecommendedAutomationRuleCard(
            task: RecommendedAutomationTask.recommendations[0],
            cardColor: Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
        )

        RecommendedAutomationRuleCard(
            task: RecommendedAutomationTask.recommendations[2],
            cardColor: Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
        )
    }
    .padding()
    .background(Color.black)

    let automationManager = CameraAutomationManager.shared

    VStack(spacing: 16) {
        AutomationRuleCard(
            rule: automationManager.automationEngine.rules[0],
            automationManager: automationManager,
            cardColor: Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255),
            accentColor: .cyan
        )

        AutomationRuleCard(
            rule: automationManager.automationEngine.rules[1],
            automationManager: automationManager,
            cardColor: Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255),
            accentColor: .green
        )
    }
    .padding()
    .background(Color.black)
}
