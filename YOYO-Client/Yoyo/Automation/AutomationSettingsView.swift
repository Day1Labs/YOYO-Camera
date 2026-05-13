import AVFoundation
import SwiftUI

struct AutomationSettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var cameraSettings: CameraSettingsState
    @ObservedObject var automationManager: CameraAutomationManager
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedTab: Int = -1 // Will be set in onAppear
    @State private var showingAddRuleSheet = false
    @State private var showingHistory = false

    // Import by code states
    @State private var showingImportCodeAlert = false
    @State private var importCode = ""
    @State private var isImporting = false
    @State private var importError: String?

    // Colors
    private let backgroundColor = Color.black
    private let cardColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let accentColor = Color.accentColor

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tabs
                    HStack(spacing: 0) {
                        TabButton(title: String.automationRecommendedTab.localized, isSelected: selectedTab == 0, accentColor: accentColor) {
                            selectedTab = 0
                        }
                        TabButton(title: String.automationMyTab.localized, isSelected: selectedTab == 1, accentColor: accentColor) {
                            selectedTab = 1
                        }
                    }
                    .padding(.vertical, 10)

                    // Content
                    ScrollView {
                        VStack(spacing: kCardSpacing) {
                            if selectedTab == 0 {
                                recommendedView
                            } else {
                                mineView
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                }

                // Bottom Button (centered)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            showingAddRuleSheet = true
                        }) {
                            Text(String.automationCreateTitle.localized)
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(height: 50)
                                .padding(.horizontal, 32)
                                .background(.white)
                                .cornerRadius(25)
                        }
                        .padding(.bottom, 25)
                        Spacer()
                    }
                    .background(
                        LinearGradient(gradient: Gradient(colors: [backgroundColor.opacity(0), backgroundColor]), startPoint: .top, endPoint: .bottom)
                            .frame(height: 100)
                    )
                }
                .ignoresSafeArea()
            }
            .navigationTitle(String.automationTaskMasterTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: {
                            cameraSettings.automationEnabled.toggle()
                        }) {
                            Image(systemName: cameraSettings.automationEnabled ? "square.stack.3d.up.fill" : "square.stack.3d.up.slash.fill")
                                .foregroundColor(cameraSettings.automationEnabled ? .white : .white.opacity(0.4))
                        }
                        Button(action: { showingImportCodeAlert = true }) {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.white)
                        }
                        Button(action: { showingHistory = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showingAddRuleSheet) {
                NavigationStack {
                    AutomationRuleEditorView(
                        rule: AutomationRule(name: "", conditions: [], actions: []),
                        engine: automationManager.automationEngine,
                        isNew: true
                    )
                }
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    AutomationHistoryView(
                        executionHistory: automationManager.executionHistory,
                        isPresented: $showingHistory,
                        onClearHistory: {
                            automationManager.executionHistory.removeAll()
                        }
                    )
                }
                .preferredColorScheme(.dark)
            }
            .overlay {
                if showingImportCodeAlert {
                    ImportCodeOverlay(
                        isPresented: $showingImportCodeAlert,
                        code: $importCode,
                        isImporting: $isImporting,
                        error: $importError,
                        onImport: performImport
                    )
                }
            }
            .fullScreenCover(isPresented: $authManager.showAuthSheet) {
                UnifiedAuthSheet()
            }
        }
        .buttonStyle(.plain)
        .preferredColorScheme(.dark)
        .trackScreen(name: "AutomationSettings")
        .onAppear {
            // If selectedTab has not been initialized yet, choose the default tab based on whether rules are empty
            if selectedTab == -1 {
                selectedTab = automationManager.automationEngine.rules.isEmpty ? 0 : 1
            }
        }
    }

    private func performImport() {
        let code = importCode.trimmingCharacters(in: .whitespaces)

        guard code.count == 6 else { return }

        isImporting = true
        importError = nil

        Task {
            do {
                let rule = try await AutomationShareService.shared.getSharedRule(code: code)
                AnalyticsManager.shared.log(.automationRuleAction(action: "import_success"))
                automationManager.automationEngine.addRule(rule)
                selectedTab = 1 // switch to"Mine"tab
                showingImportCodeAlert = false
                importCode = ""
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }

    var mineView: some View {
        VStack(spacing: kCardSpacing) {
            if automationManager.automationEngine.rules.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(Color.white.opacity(0.2))

                        Text(String.automationNoTasks.localized)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.top, 128)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(automationManager.automationEngine.rules) { rule in
                    NavigationLink(destination: AutomationRuleEditorView(rule: rule, engine: automationManager.automationEngine)) {
                        AutomationRuleCard(
                            rule: rule,
                            automationManager: automationManager,
                            cardColor: cardColor,
                            accentColor: accentColor
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    var recommendedView: some View {
        VStack(spacing: kCardSpacing) {
            ForEach(RecommendedAutomationTask.recommendations) { task in
                NavigationLink(destination: RecommendedTaskDetailView(
                    task: task,
                    engine: automationManager.automationEngine,
                    onTaskAdded: {
                        selectedTab = 1
                    }
                )) {
                    RecommendedAutomationRuleCard(
                        task: task,
                        cardColor: cardColor
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Import Code UI Components

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .gray)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(height: 3)
                    .frame(width: 24)
                    .cornerRadius(1.5)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
