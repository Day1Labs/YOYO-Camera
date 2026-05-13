import Foundation
import SwiftUI

/// Quick task manager - manages tasks added to the quick panel
final class QuickTaskManager: ObservableObject {
    static let shared = QuickTaskManager()

    /// Rule ID list for quick tasks
    @Published var quickTaskRuleIds: [String] = []

    private let userDefaultsKey = "com.day1-labs.yoyo.quicktask.ruleIds"

    private init() {
        loadQuickTasks()
    }

    /// Add a task to the quick panel
    func addQuickTask(ruleId: String) {
        guard !quickTaskRuleIds.contains(ruleId) else { return }
        quickTaskRuleIds.append(ruleId)
        saveQuickTasks()
    }

    /// Remove a task from the quick panel
    func removeQuickTask(ruleId: String) {
        quickTaskRuleIds.removeAll { $0 == ruleId }
        saveQuickTasks()
    }

    /// Check whether a task is in the quick panel
    func isInQuickTasks(ruleId: String) -> Bool {
        quickTaskRuleIds.contains(ruleId)
    }

    /// Toggle the quick panel state of a task
    func toggleQuickTask(ruleId: String) {
        if isInQuickTasks(ruleId: ruleId) {
            removeQuickTask(ruleId: ruleId)
        } else {
            addQuickTask(ruleId: ruleId)
        }
    }

    /// Reorder quick tasks
    func reorderQuickTasks(from source: IndexSet, to destination: Int) {
        quickTaskRuleIds.move(fromOffsets: source, toOffset: destination)
        saveQuickTasks()
    }

    // MARK: - persistence

    private func saveQuickTasks() {
        do {
            let data = try JSONEncoder().encode(quickTaskRuleIds)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("✅ 快捷任务已保存: \(quickTaskRuleIds.count) 个")
        } catch {
            print("❌ 保存快捷任务失败: \(error)")
        }
    }

    private func loadQuickTasks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("ℹ️ 未找到已保存的快捷任务")
            return
        }

        do {
            quickTaskRuleIds = try JSONDecoder().decode([String].self, from: data)
            print("✅ 已加载快捷任务: \(quickTaskRuleIds.count) 个")
        } catch {
            print("❌ 加载快捷任务失败: \(error)")
            quickTaskRuleIds = []
        }
    }
}
