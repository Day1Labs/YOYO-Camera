import AuthenticationServices
import AVFoundation
import SwiftUI
import UIKit

struct AutomationRuleEditorView: View {
    @State var rule: AutomationRule
    var engine: AutomationEngine
    var isNew: Bool = false
    @Environment(\.dismiss) private var dismiss

    // Share states
    @State private var showingShareSheet = false
    @State private var shareCode: String?
    @State private var isSharing = false
    @State private var shareError: String?
    @StateObject private var authManager = AuthManager.shared

    @State private var showingConditionPicker = false
    @State private var showingActionPicker = false

    // Dark theme colors
    private let backgroundColor = Color.black
    private let cardColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let accentColor = Color.accentColor

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Name Input with Clear Button
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                TextField(String.automationRuleNamePlaceholder.localized, text: $rule.name)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                                    .submitLabel(.done)

                                if rule.name.isEmpty {
                                    Button(action: {
                                        rule.name = AutomationRuleNameGenerator.generate(for: rule)
                                    }) {
                                        Image(systemName: "wand.and.stars")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 20))
                                    }
                                } else {
                                    Button(action: {
                                        rule.name = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 20))
                                    }
                                }
                            }
                            .padding()
                            .background(cardColor)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)

                        // IF Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(String.automationIfTitle.localized)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)

                                Spacer()

                                // condition logic switcher
                                HStack(spacing: 0) {
                                    Button(action: {
                                        rule.conditionLogic = .and
                                    }) {
                                        Text(String.automationConditionLogicAll.localized)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(rule.conditionLogic == .and ? .black : .white.opacity(0.6))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(rule.conditionLogic == .and ? accentColor : Color.clear)
                                    }

                                    Button(action: {
                                        rule.conditionLogic = .or
                                    }) {
                                        Text(String.automationConditionLogicAny.localized)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(rule.conditionLogic == .or ? .black : .white.opacity(0.6))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(rule.conditionLogic == .or ? accentColor : Color.clear)
                                    }
                                }
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }

                            Text(rule.conditionLogic == .and
                                ? String.automationConditionLogicAllDesc.localized
                                : String.automationConditionLogicAnyDesc.localized)
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)

                            // Conditions List
                            if !rule.conditions.isEmpty {
                                ForEach(rule.conditions.indices, id: \.self) { index in
                                    ConditionCardView(
                                        condition: rule.conditions[index],
                                        onDelete: {
                                            rule.conditions.remove(at: index)
                                        }
                                    )
                                }
                            }

                            // Add Button
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                showingConditionPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16))
                                    Text(addConditionButtonText)
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)

                        // THEN Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text(String.automationThenTitle.localized)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)

                            Text(String.automationActionsPrompt.localized)
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.5))

                            // Actions List
                            if !rule.actions.isEmpty {
                                ForEach(rule.actions.indices, id: \.self) { index in
                                    ActionCardView(
                                        action: rule.actions[index],
                                        onDelete: {
                                            rule.actions.remove(at: index)
                                        }
                                    )
                                }
                            }

                            // Add Button
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                showingActionPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16))
                                    Text(String.automationAddAction.localized)
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(accentColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)

                        // execution frequency section
                        VStack(alignment: .leading, spacing: 16) {
                            Text(String.automationExecutionFrequency.localized)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)

                            Text(String.automationExecutionFrequencyDesc.localized)
                                .font(.system(size: 14))
                                .foregroundColor(Color.white.opacity(0.5))

                            ExecutionIntervalPickerView(interval: $rule.executionInterval)
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 100)
                    }
                }

                // Bottom Button
                VStack {
                    Button(action: {
                        // pre-save validation:if the task name is empty, generate one automatically
                        if rule.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            rule.name = AutomationRuleNameGenerator.generate(for: rule)
                        }

                        if isNew {
                            engine.addRule(rule)
                            AnalyticsManager.shared.log(.automationRuleAction(action: "create"))
                        } else {
                            engine.updateRule(rule)
                            AnalyticsManager.shared.log(.automationRuleAction(action: "update"))
                        }
                        dismiss()
                    }) {
                        Text(String.automationConfirmButton.localized)
                            .font(.headline)
                            .foregroundColor(rule.actions.isEmpty ? .gray : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(rule.actions.isEmpty ? Color(white: 0.3) : .white)
                            .cornerRadius(25)
                    }
                    .disabled(rule.actions.isEmpty)
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

            // Share Result Overlay
            if showingShareSheet, let code = shareCode {
                AutomationShareResultView(
                    code: code,
                    onCopy: {
                        UIPasteboard.general.string = code
                        withAnimation {
                            showingShareSheet = false
                        }
                    },
                    onDismiss: {
                        withAnimation {
                            showingShareSheet = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(100)
            }
        }
        .navigationTitle(isNew ? String.automationCreateTitle.localized : String.automationEditTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isNew {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { handleShareTap() }) {
                        if isSharing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(isSharing)
                }
            }
        }
        .fullScreenCover(isPresented: $showingConditionPicker) {
            NavigationStack {
                AutomationRulePickerView(selectionType: .condition, onSelectCondition: { condition in
                    rule.conditions.append(condition)
                })
            }
        }
        .fullScreenCover(isPresented: $showingActionPicker) {
            NavigationStack {
                AutomationRulePickerView(selectionType: .action, onSelectAction: { action in
                    rule.actions.append(action)
                })
            }
        }
        .alert(String.automationShareErrorTitle.localized, isPresented: .init(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button(String.filterImportConfirm.localized, role: .cancel) {}
        } message: {
            if let error = shareError {
                Text(error)
            }
        }
        .fullScreenCover(isPresented: $authManager.showAuthSheet) {
            UnifiedAuthSheet()
        }
        .preferredColorScheme(.dark)
        .trackScreen(name: "AutomationEditor")
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
                AnalyticsManager.shared.log(.automationRuleAction(action: "share_success"))
                shareCode = code
                rule.shareCode = code // update the share code in the rule
                withAnimation {
                    showingShareSheet = true
                }
            } catch {
                shareError = error.localizedDescription
            }
            isSharing = false
        }
    }

    var addConditionButtonText: String {
        switch rule.conditionLogic {
        case .and: return String.automationLogicAnd.localized
        case .or: return String.automationLogicOr.localized
        }
    }
}

// MARK: - Condition Card View

struct ConditionCardView: View {
    let condition: AutomationCondition
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: condition.iconSystemName)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(condition.titleText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Text(condition.detailText)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            Spacer()

            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Action Card View

struct ActionCardView: View {
    let action: AutomationAction
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: action.iconSystemName)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(action.titleText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Text(action.detailText)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.5))
            }

            Spacer()

            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Execution Interval Picker View

struct ExecutionIntervalPickerView: View {
    @Binding var interval: TimeInterval

    private enum QuickPreset: CaseIterable {
        case unlimited, tenSeconds, oneMinute, custom

        var displayName: String {
            switch self {
            case .unlimited: return String.automationExecutionUnlimited.localized
            case .tenSeconds: return ExecutionIntervalSupport.displayText(for: 10)
            case .oneMinute: return ExecutionIntervalSupport.displayText(for: 60)
            case .custom: return String.commonCustom.localized
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .unlimited: return 0
            case .tenSeconds: return 10
            case .oneMinute: return 60
            case .custom: return -1
            }
        }

        static func from(_ interval: TimeInterval) -> QuickPreset {
            switch interval {
            case 0: return .unlimited
            case 10: return .tenSeconds
            case 60: return .oneMinute
            default: return .custom
            }
        }
    }

    @State private var selectedPreset: QuickPreset = .unlimited
    @State private var sliderValue: Double = 0 // log-scale value 0~1

    private let accentColor = Color.accentColor

    // slider range: 5 seconds ~ 1 day (86400 seconds), use logarithmic scaling
    private let minSeconds: Double = 5
    private let maxSeconds: Double = 86400

    var body: some View {
        VStack(spacing: 12) {
            // 4 preset buttons
            HStack(spacing: 8) {
                ForEach(QuickPreset.allCases, id: \.self) { preset in
                    Button(action: {
                        selectedPreset = preset
                        if preset != .custom {
                            interval = preset.seconds
                        } else {
                            // when switching to custom, set the default to 30 seconds
                            if interval == 0 || interval == 10 || interval == 60 {
                                interval = 30
                            }
                            sliderValue = secondsToSlider(interval)
                        }
                    }) {
                        Text(preset.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedPreset == preset ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(selectedPreset == preset ? accentColor : Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
            }

            // custom slider
            if selectedPreset == .custom {
                VStack(spacing: 8) {
                    Slider(value: $sliderValue, in: 0 ... 1)
                        .tint(accentColor)
                        .onChange(of: sliderValue) { _, newValue in
                            interval = sliderToSeconds(newValue)
                        }

                    HStack {
                        Text(String.automationIntervalMinLabel.localized)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text(ExecutionIntervalSupport.displayText(for: interval))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accentColor)
                        Spacer()
                        Text(String.automationIntervalMaxLabel.localized)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            selectedPreset = QuickPreset.from(interval)
            if selectedPreset == .custom {
                sliderValue = secondsToSlider(interval)
            }
        }
    }

    /// Log scale: slider (0~1) -> seconds (5~86400)
    private func sliderToSeconds(_ value: Double) -> TimeInterval {
        ExecutionIntervalSupport.sliderToSeconds(value, minSeconds: minSeconds, maxSeconds: maxSeconds)
    }

    /// Log scale: seconds (5~86400) -> slider (0~1)
    private func secondsToSlider(_ seconds: TimeInterval) -> Double {
        ExecutionIntervalSupport.secondsToSlider(seconds, minSeconds: minSeconds, maxSeconds: maxSeconds)
    }
}

// MARK: - Share Result View

struct AutomationShareResultView: View {
    let code: String
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 24) {
                // Title with Icon
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)

                    Text(String.automationShareSuccessTitle.localized)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.top, 16)

                Text(String.automationShareSuccessDesc.localized)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, -16)

                // Code Box
                HStack {
                    Text(code)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                        .kerning(2)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 32)
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                // Copy Button
                Button(action: onCopy) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text(String.automationShareCopyCode.localized)
                    }
                    .fontWeight(.medium)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white)
                    .cornerRadius(27)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .padding(24)
            .background(Color(red: 0.15, green: 0.15, blue: 0.16))
            .cornerRadius(24)
            .overlay(
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .padding(12),
                alignment: .topTrailing
            )
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
            .padding(32)
        }
    }
}
