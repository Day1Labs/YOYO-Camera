import AVFoundation
import Combine
import CoreLocation
import Foundation
import Photos
import UIKit

// MARK: - Permission type enumeration

enum PermissionType: String, CaseIterable {
    case camera
    case microphone
    case photoLibrary
    case location

    var displayName: String {
        switch self {
        case .camera: return String.permissionCameraTitle.localized
        case .microphone: return String.permissionMicrophoneTitle.localized
        case .photoLibrary: return String.permissionPhotoLibraryTitle.localized
        case .location: return String.permissionLocationTitle.localized
        }
    }

    var description: String {
        switch self {
        case .camera: return String.permissionCameraDescription.localized
        case .microphone: return String.permissionMicrophoneDescription.localized
        case .photoLibrary: return String.permissionPhotoLibraryDescription.localized
        case .location: return String.permissionLocationDescription.localized
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .photoLibrary: return "photo.on.rectangle"
        case .location: return "location.fill"
        }
    }

    var deniedMessage: String {
        switch self {
        case .camera: return String.permissionCameraDenied.localized
        case .microphone: return String.permissionMicrophoneDenied.localized
        case .photoLibrary: return String.permissionPhotoLibraryDenied.localized
        case .location: return String.permissionLocationDenied.localized
        }
    }
}

// MARK: - Permission status enumeration

enum PermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    case limited // Only for photo albums

    var isGranted: Bool {
        self == .authorized || self == .limited
    }
}

// MARK: - permission manager

final class PermissionManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var cameraStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var photoLibraryStatus: PermissionStatus = .notDetermined
    @Published var locationStatus: PermissionStatus = .notDetermined

    /// The type of permission prompt that currently needs to be displayed
    @Published var pendingPermissionAlert: PermissionType?

    /// Do you need to show permissions to boot (first boot)
    @Published var needsOnboarding: Bool = false

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKeys {
        static let hasCompletedOnboarding = "hasCompletedPermissionOnboarding"
    }

    // MARK: - Computed Properties

    var hasCameraPermission: Bool {
        cameraStatus.isGranted
    }

    var hasMicrophonePermission: Bool {
        microphoneStatus.isGranted
    }

    var hasPhotoLibraryPermission: Bool {
        photoLibraryStatus.isGranted
    }

    var hasLocationPermission: Bool {
        locationStatus.isGranted
    }

    /// Whether the album is in restricted access mode
    var isPhotoLibraryLimited: Bool {
        photoLibraryStatus == .limited
    }

    // MARK: - Legacy Compatibility

    /// showingPermissionAlert compatible with old code
    var showingPermissionAlert: Bool {
        get { pendingPermissionAlert != nil }
        set { if !newValue { pendingPermissionAlert = nil } }
    }

    // MARK: - Private Properties

    private let locationAuthManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton

    static let shared = PermissionManager()

    // MARK: - Initialization

    override init() {
        super.init()

        // Synchronous initialization permission status
        refreshAllPermissions()

        // Check if you need to show boot
        checkOnboardingStatus()

        // Set location permission proxy
        locationAuthManager.delegate = self

        // The monitoring application returns to the foreground and refreshes the permission status
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.refreshAllPermissions()
            }
            .store(in: &cancellables)
    }

    // MARK: - Boot state management

    /// Check if you need to show permissions to boot
    private func checkOnboardingStatus() {
        let hasCompleted = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)

        // If booting is not completed and core permissions are not granted, boot is displayed
        if !hasCompleted, cameraStatus == .notDetermined || photoLibraryStatus == .notDetermined {
            needsOnboarding = true
        }
    }

    /// Complete permission guidance
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasCompletedOnboarding)
        needsOnboarding = false
    }

    /// Reset boot state (for testing)
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        needsOnboarding = true
    }

    // MARK: - Refresh all permission status

    func refreshAllPermissions() {
        refreshCameraPermission()
        refreshMicrophonePermission()
        refreshPhotoLibraryPermission()
        refreshLocationPermission()
    }

    // MARK: - Camera permissions

    func refreshCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let mappedStatus = mapAVAuthorizationStatus(status)
        if Thread.isMainThread {
            cameraStatus = mappedStatus
        } else {
            DispatchQueue.main.async {
                self.cameraStatus = mappedStatus
            }
        }
    }

    func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraStatus = .authorized
        case .notDetermined:
            requestCameraPermission()
        case .denied, .restricted:
            cameraStatus = status == .denied ? .denied : .restricted
            pendingPermissionAlert = .camera
        @unknown default:
            cameraStatus = .denied
            pendingPermissionAlert = .camera
        }
    }

    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraStatus = granted ? .authorized : .denied
                if !granted {
                    self?.pendingPermissionAlert = .camera
                }
            }
        }
    }

    // MARK: - Microphone permissions

    func refreshMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let mappedStatus = mapAVAuthorizationStatus(status)
        if Thread.isMainThread {
            microphoneStatus = mappedStatus
        } else {
            DispatchQueue.main.async {
                self.microphoneStatus = mappedStatus
            }
        }
    }

    func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneStatus = .authorized
        case .notDetermined:
            requestMicrophonePermission()
        case .denied, .restricted:
            microphoneStatus = status == .denied ? .denied : .restricted
            pendingPermissionAlert = .microphone
        @unknown default:
            microphoneStatus = .denied
            pendingPermissionAlert = .microphone
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphoneStatus = granted ? .authorized : .denied
                if !granted {
                    self?.pendingPermissionAlert = .microphone
                }
            }
        }
    }

    // MARK: - Album permissions

    func refreshPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let mappedStatus = mapPHAuthorizationStatus(status)
        if Thread.isMainThread {
            photoLibraryStatus = mappedStatus
        } else {
            DispatchQueue.main.async {
                self.photoLibraryStatus = mappedStatus
            }
        }
    }

    func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            photoLibraryStatus = .authorized
        case .limited:
            photoLibraryStatus = .limited
        case .notDetermined:
            requestPhotoLibraryPermission()
        case .denied, .restricted:
            photoLibraryStatus = status == .denied ? .denied : .restricted
            pendingPermissionAlert = .photoLibrary
        @unknown default:
            photoLibraryStatus = .denied
            pendingPermissionAlert = .photoLibrary
        }
    }

    func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.photoLibraryStatus = self?.mapPHAuthorizationStatus(status) ?? .denied
                if status == .denied || status == .restricted {
                    self?.pendingPermissionAlert = .photoLibrary
                }
            }
        }
    }

    // MARK: - location permissions

    func refreshLocationPermission() {
        let status = locationAuthManager.authorizationStatus
        let mappedStatus = mapCLAuthorizationStatus(status)
        if Thread.isMainThread {
            locationStatus = mappedStatus
        } else {
            DispatchQueue.main.async {
                self.locationStatus = mappedStatus
            }
        }
    }

    func checkLocationPermission() {
        let status = locationAuthManager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationStatus = .authorized
        case .notDetermined:
            requestLocationPermission()
        case .denied, .restricted:
            locationStatus = status == .denied ? .denied : .restricted
            pendingPermissionAlert = .location
        @unknown default:
            locationStatus = .denied
            pendingPermissionAlert = .location
        }
    }

    func requestLocationPermission() {
        locationAuthManager.requestWhenInUseAuthorization()
    }

    // MARK: - general method

    /// Get the status of a specified permission type
    func status(for type: PermissionType) -> PermissionStatus {
        switch type {
        case .camera: return cameraStatus
        case .microphone: return microphoneStatus
        case .photoLibrary: return photoLibraryStatus
        case .location: return locationStatus
        }
    }

    /// Check specific permissions
    func check(_ type: PermissionType) {
        switch type {
        case .camera: checkCameraPermission()
        case .microphone: checkMicrophonePermission()
        case .photoLibrary: checkPhotoLibraryPermission()
        case .location: checkLocationPermission()
        }
    }

    /// Request specific permissions
    func request(_ type: PermissionType) {
        switch type {
        case .camera: requestCameraPermission()
        case .microphone: requestMicrophonePermission()
        case .photoLibrary: requestPhotoLibraryPermission()
        case .location: requestLocationPermission()
        }
    }

    /// Open system settings
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Clear permission prompt
    func dismissPermissionAlert() {
        pendingPermissionAlert = nil
    }

    // MARK: - Private Helpers

    private func mapAVAuthorizationStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    private func mapPHAuthorizationStatus(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    private func mapCLAuthorizationStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async { [weak self] in
            self?.locationStatus = self?.mapCLAuthorizationStatus(status) ?? .denied
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization _: CLAuthorizationStatus) {
        locationManagerDidChangeAuthorization(manager)
    }
}
