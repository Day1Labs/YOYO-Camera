import Combine
import Foundation
import SwiftUI

// MARK: - Global Notification Definitions

extension Notification.Name {
    static let cameraUserAction = Notification.Name("cameraUserAction")
    static let cameraCaptureStateChanged = Notification.Name("cameraCaptureStateChanged")
    static let cameraSaveFinished = Notification.Name("cameraSaveFinished")
}

enum CameraNotificationKeys {
    static let action = "action"
    static let captureState = "captureState"
    static let saveSuccess = "saveSuccess"
    static let saveError = "saveError"
}

// MARK: - Camera View State Manager

@MainActor
final class CameraViewState: ObservableObject {
    // MARK: - Singleton

    static let shared = CameraViewState()

    // MARK: - User Action Intents

    enum UserAction {
        case startCapture
        case startTimerCapture
        case cancel
        case stopRecording
        case reset
        case requestAIInspiration
    }

    /// Broadcast an action
    func sendAction(_ action: UserAction) {
        print("📡 [ViewState] Broadcasting action: \(action)")
        NotificationCenter.default.post(
            name: .cameraUserAction,
            object: nil,
            userInfo: [CameraNotificationKeys.action: action]
        )
    }

    // MARK: - Capture Result State

    // Capture result state is now managed by `CameraCaptureService`

    // MARK: - UI State

    @Published var showingPhotoGallery = false
    @Published var showingFilterGallery = false
    @Published var showingSettings = false
    @Published var showingAutomationSettings = false
    @Published var isInspirationMaximized = false
    @Published var currentToast: ToastMessage? = nil
    @Published var showLensSwitchButton: Bool = true

    // MARK: - Device Rotation State

    @Published var rotation: Double = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupOrientationObservation()
    }

    private func setupOrientationObservation() {
        // Observe device orientation changes
        OrientationManager.shared.$currentDeviceOrientation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceOrientation in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.rotation = OrientationManager.rotationAngle(deviceOrientation)
                }
            }
            .store(in: &cancellables)
    }

    /// Clear the error state for recovery
    func clearError() {
        // Clear the error toast
        currentToast = nil
    }

    /// Force-reset the state
    func forceReset() {
        // Clear the error toast as well
        if currentToast?.type == .error {
            currentToast = nil
        }
    }

    // MARK: - UI State Management

    func resetUIState() {
        showingPhotoGallery = false
        showingFilterGallery = false
        isInspirationMaximized = false
    }

    /// Show a toast message
    func showToast(type: ToastType, message: String, duration: TimeInterval = 3.0, customIcon: String? = nil) {
        let toast = ToastMessage(type: type, message: message, duration: duration, customIcon: customIcon)
        currentToast = toast

        // Auto-hide
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if currentToast?.id == toast.id {
                currentToast = nil
            }
        }
    }

    /// Show a success message
    func showSuccess(_ message: String, customIcon: String? = nil) {
        showToast(type: .success, message: message, customIcon: customIcon)
    }

    /// Show an error message
    func showError(_ message: String, customIcon: String? = nil) {
        showToast(type: .error, message: message, customIcon: customIcon)
    }

    /// Show a warning message
    func showWarning(_ message: String, customIcon: String? = nil) {
        showToast(type: .warning, message: message, customIcon: customIcon)
    }

    /// Show an informational message
    func showInfo(_ message: String, customIcon: String? = nil) {
        showToast(type: .info, message: message, customIcon: customIcon)
    }
}
