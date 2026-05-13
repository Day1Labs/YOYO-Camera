import AVFoundation
import SwiftUI

// MARK: - Recommended task model

struct RecommendedAutomationTask: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let conditions: [ConditionDisplay]
    let actions: [ActionDisplay]

    /// Conditions for display
    struct ConditionDisplay: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    /// Actions for display
    struct ActionDisplay: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let subtitle: String
    }

    /// Convert to an actual automation rule
    func toAutomationRule() -> AutomationRule {
        // Build rules according to the specific recommended task here
        // For simplicity, each recommended task stores the actual conditions and actions
        AutomationRule(
            name: title,
            conditions: actualConditions,
            actions: actualActions,
            priority: 50,
            isEnabled: true,
            requireConfirmation: true
        )
    }

    // Actual conditions and actions (used to create rules)
    let actualConditions: [AutomationCondition]
    let actualActions: [AutomationAction]
}

// MARK: - Preset recommended tasks

extension RecommendedAutomationTask {
    static let recommendations: [RecommendedAutomationTask] = [
        // 1. portrait optimization
        .init(
            icon: "person.fill",
            iconColor: Color(red: 1.0, green: 0.6, blue: 0.4),
            title: String.recTaskPortraitTitle.localized,
            description: String.recTaskPortraitDesc.localized,
            conditions: [
                .init(icon: "person.fill", title: String.conditionTypeScene.localized, subtitle: String.scenePortrait.localized),
            ],
            actions: [
                .init(icon: "arrow.up.left.and.arrow.down.right", iconColor: .cyan, title: String.actionTypeZoom.localized, subtitle: "2.0x"),
                .init(icon: "sun.max", iconColor: .orange, title: String.actionTypeExposure.localized, subtitle: "+0.5"),
                .init(icon: "scope", iconColor: .green, title: String.actionTypeFocus.localized, subtitle: String.detailSubjectFace.localized),
            ],
            actualConditions: [.sceneIn([.portrait])],
            actualActions: [
                .setZoom(2.0),
                .setExposureBias(0.5),
                .focusOnSubject,
            ]
        ),

        // 2. cityscape/city
        .init(
            icon: "building.2.fill",
            iconColor: Color(red: 0.4, green: 0.7, blue: 1.0),
            title: String.recTaskCityTitle.localized,
            description: String.recTaskCityDesc.localized,
            conditions: [
                .init(icon: "building.2.fill", title: String.conditionTypeScene.localized, subtitle: String.sceneCityBuilding.localized),
            ],
            actions: [
                .init(icon: "arrow.up.left.and.arrow.down.right", iconColor: .cyan, title: String.actionTypeZoom.localized, subtitle: "1.0x"),
                .init(icon: "sun.max", iconColor: .orange, title: String.actionTypeExposure.localized, subtitle: "-0.5"),
                .init(icon: "bolt.slash.fill", iconColor: .yellow, title: String.actionTypeFlash.localized, subtitle: String.commonOff.localized),
            ],
            actualConditions: [.sceneIn([.cityscape, .vehicle])],
            actualActions: [
                .setZoom(1.0),
                .setExposureBias(-0.5),
                .setFlashMode(.off),
            ]
        ),

        // 3. food photography
        .init(
            icon: "fork.knife",
            iconColor: Color(red: 1.0, green: 0.8, blue: 0.3),
            title: String.recTaskFoodTitle.localized,
            description: String.recTaskFoodDesc.localized,
            conditions: [
                .init(icon: "fork.knife", title: String.conditionTypeScene.localized, subtitle: String.sceneFood.localized),
            ],
            actions: [
                .init(icon: "sun.max", iconColor: .orange, title: String.actionTypeExposure.localized, subtitle: "+0.5"),
                .init(icon: "bolt.slash.fill", iconColor: .yellow, title: String.actionTypeFlash.localized, subtitle: String.commonOff.localized),
                .init(icon: "camera.filters", iconColor: .pink, title: String.actionTypeFilter.localized, subtitle: String.filterGoldenGate.localized),
            ],
            actualConditions: [.sceneIn([.food])],
            actualActions: [
                .setExposureBias(0.5),
                .setFlashMode(.off),
                .setFilter(.builtin("GoldenGate")),
            ]
        ),

        // 4. low-light compensation
        .init(
            icon: "moon.stars.fill",
            iconColor: Color(red: 0.6, green: 0.5, blue: 1.0),
            title: String.recTaskLowLightTitle.localized,
            description: String.recTaskLowLightDesc.localized,
            conditions: [
                .init(icon: "moon.fill", title: String.conditionTypeLighting.localized, subtitle: String.lightingDarkDim.localized),
            ],
            actions: [
                .init(icon: "sun.max", iconColor: .orange, title: String.actionTypeExposure.localized, subtitle: "+0.5"),
                .init(icon: "bolt.fill", iconColor: .yellow, title: String.actionTypeFlash.localized, subtitle: String.commonOn.localized),
            ],
            actualConditions: [.lightingInList([.dark, .dim])],
            actualActions: [
                .addExposureBias(0.5),
                .setFlashMode(.on),
            ]
        ),

        // 5. pet snapshot
        .init(
            icon: "pawprint.fill",
            iconColor: Color(red: 1.0, green: 0.5, blue: 0.7),
            title: String.recTaskPetTitle.localized,
            description: String.recTaskPetDesc.localized,
            conditions: [
                .init(icon: "pawprint.fill", title: String.conditionTypeScene.localized, subtitle: String.scenePetAnimal.localized),
            ],
            actions: [
                .init(icon: "arrow.up.left.and.arrow.down.right", iconColor: .cyan, title: String.actionTypeZoom.localized, subtitle: "2.0x"),
                .init(icon: "scope", iconColor: .green, title: String.actionTypeFocus.localized, subtitle: String.subjectAnimal.localized),
                .init(icon: "bolt.slash.fill", iconColor: .yellow, title: String.actionTypeFlash.localized, subtitle: String.commonOff.localized),
            ],
            actualConditions: [.sceneIn([.pet, .wildlife])],
            actualActions: [
                .setZoom(2.0),
                .focusOnSubject,
                .setFlashMode(.off),
            ]
        ),

        // 6. sunset mood enhancement
        .init(
            icon: "sunset.fill",
            iconColor: Color(red: 1.0, green: 0.4, blue: 0.2),
            title: String.recTaskSunsetTitle.localized,
            description: String.recTaskSunsetDesc.localized,
            conditions: [
                .init(icon: "clock.fill", title: String.automationTime.localized, subtitle: "17:00 - 19:30"),
            ],
            actions: [
                .init(icon: "camera.filters", iconColor: .orange, title: String.actionTypeFilter.localized, subtitle: String.filterGoldenGate.localized),
                .init(icon: "sun.max", iconColor: .orange, title: String.actionTypeExposure.localized, subtitle: "+0.5"),
            ],
            actualConditions: [.timeInRange(startHour: 17, startMinute: 0, endHour: 19, endMinute: 30)],
            actualActions: [
                .setFilter(.builtin("GoldenGate")),
                .addExposureBias(0.5),
            ]
        ),

        // 7. sports snapshot
        .init(
            icon: "figure.run",
            iconColor: Color(red: 0.2, green: 0.8, blue: 0.4),
            title: String.recTaskSportsTitle.localized,
            description: String.recTaskSportsDesc.localized,
            conditions: [
                .init(icon: "figure.run", title: String.conditionTypeScene.localized, subtitle: String.sceneSports.localized),
            ],
            actions: [
                .init(icon: "timer", iconColor: .blue, title: String.actionTypeShutter.localized, subtitle: "1/1000s"),
                .init(icon: "bolt.slash.fill", iconColor: .yellow, title: String.actionTypeFlash.localized, subtitle: String.commonOff.localized),
            ],
            actualConditions: [.sceneIn([.sports])],
            actualActions: [
                .setShutterSpeed(0.001),
                .setFlashMode(.off),
            ]
        ),

        // 8. flower close-up
        .init(
            icon: "leaf.fill",
            iconColor: Color(red: 0.4, green: 0.8, blue: 0.2),
            title: String.recTaskFlowerTitle.localized,
            description: String.recTaskFlowerDesc.localized,
            conditions: [
                .init(icon: "leaf.fill", title: String.conditionTypeScene.localized, subtitle: String.scenePlant.localized),
            ],
            actions: [
                .init(icon: "magnifyingglass", iconColor: .blue, title: String.actionTypeZoom.localized, subtitle: "2.0x"),
                .init(icon: "scope", iconColor: .green, title: String.actionTypeFocus.localized, subtitle: String.scenePlant.localized),
            ],
            actualConditions: [.sceneIn([.plant])],
            actualActions: [
                .setZoom(2.0),
                .focusOnSubject,
            ]
        ),

        // 9. overexposure correction
        .init(
            icon: "sun.max.trianglebadge.exclamationmark.fill",
            iconColor: Color(red: 1.0, green: 0.3, blue: 0.3),
            title: String.recTaskOverexposureTitle.localized,
            description: String.recTaskOverexposureDesc.localized,
            conditions: [
                .init(icon: "sun.max.fill", title: String.conditionTypeExposureStatus.localized, subtitle: String.exposureOverexposed.localized),
            ],
            actions: [
                .init(icon: "sun.min", iconColor: .orange, title: String.actionTypeExposure.localized, subtitle: "-1.0"),
                .init(icon: "message.fill", iconColor: .gray, title: String.actionTypeToast.localized, subtitle: String.toastCorrected.localized),
            ],
            actualConditions: [.isOverexposed],
            actualActions: [
                .addExposureBias(-1.0),
                .showToast(type: .info, message: String.toastExposureReduced.localized, duration: 2.0),
            ]
        ),
    ]
}
