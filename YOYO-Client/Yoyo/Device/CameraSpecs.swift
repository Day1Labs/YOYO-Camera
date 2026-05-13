import Foundation

// MARK: - devicecameraparametersconfigure

struct CameraDeviceCameraSpec {
    let ultraWideFocalLength: Double? // ultra-widefocal length (35mm)
    let wideFocalLength: Double // wide camerafocal length (35mm)
    let telephotoFocalLength: Double? // telephotofocal length (35mm)

    let ultraWidePhysicalFocalLength: Double? // ultra-widephysicalfocal length
    let widePhysicalFocalLength: Double? // wide cameraphysicalfocal length
    let telephotoPhysicalFocalLength: Double? // telephotophysicalfocal length

    let deviceName: String

    init(
        ultraWideFocalLength: Double? = nil,
        wideFocalLength: Double,
        telephotoFocalLength: Double? = nil,
        ultraWidePhysicalFocalLength: Double? = nil,
        widePhysicalFocalLength: Double? = nil,
        telephotoPhysicalFocalLength: Double? = nil,
        deviceName: String
    ) {
        self.ultraWideFocalLength = ultraWideFocalLength
        self.wideFocalLength = wideFocalLength
        self.telephotoFocalLength = telephotoFocalLength
        self.ultraWidePhysicalFocalLength = ultraWidePhysicalFocalLength
        self.widePhysicalFocalLength = widePhysicalFocalLength
        self.telephotoPhysicalFocalLength = telephotoPhysicalFocalLength
        self.deviceName = deviceName
    }
}

// MARK: - devicecameraparameters

enum CameraSpecs {
    static let specs: [String: CameraDeviceCameraSpec] = [
        // iPhone 17 (2025)
        "iPhone18,3": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: nil, deviceName: "iPhone 17"),
        "iPhone18,1": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 120, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: 15.66, deviceName: "iPhone 17 Pro"),
        "iPhone18,2": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 120, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: 15.66, deviceName: "iPhone 17 Pro Max"),
        "iPhone18,4": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: nil, deviceName: "iPhone Air"),

        // iPhone 16 (2024)
        "iPhone17,3": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: nil, deviceName: "iPhone 16"),
        "iPhone17,4": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: nil, deviceName: "iPhone 16 Plus"),
        "iPhone17,1": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 120, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: 15.66, deviceName: "iPhone 16 Pro"),
        "iPhone17,2": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 120, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.765, telephotoPhysicalFocalLength: 15.66, deviceName: "iPhone 16 Pro Max"),

        // iPhone 15 (2023)
        "iPhone15,4": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 5.96, telephotoPhysicalFocalLength: nil, deviceName: "iPhone 15"),
        "iPhone15,5": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 5.96, telephotoPhysicalFocalLength: nil, deviceName: "iPhone 15 Plus"),
        "iPhone16,1": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 77, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.76, telephotoPhysicalFocalLength: 9.0, deviceName: "iPhone 15 Pro"),
        "iPhone16,2": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 120, ultraWidePhysicalFocalLength: 2.22, widePhysicalFocalLength: 6.76, telephotoPhysicalFocalLength: 15.66, deviceName: "iPhone 15 Pro Max"),

        // iPhone 14 (2022)
        "iPhone14,7": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 14"),
        "iPhone14,8": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 14 Plus"),
        "iPhone15,2": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 77, deviceName: "iPhone 14 Pro"),
        "iPhone15,3": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 24, telephotoFocalLength: 77, deviceName: "iPhone 14 Pro Max"),

        // iPhone 13 (2021)
        "iPhone14,5": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 13"),
        "iPhone14,2": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 13 mini"),
        "iPhone14,3": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 77, deviceName: "iPhone 13 Pro"),
        "iPhone14,4": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 77, deviceName: "iPhone 13 Pro Max"),

        // iPhone 12 (2020)
        "iPhone13,2": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 12"),
        "iPhone13,1": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 12 mini"),
        "iPhone13,3": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 65, deviceName: "iPhone 12 Pro"),
        "iPhone13,4": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 65, deviceName: "iPhone 12 Pro Max"),

        // iPhone 11 (2019)
        "iPhone12,1": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone 11"),
        "iPhone12,3": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 52, deviceName: "iPhone 11 Pro"),
        "iPhone12,5": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 52, deviceName: "iPhone 11 Pro Max"),

        // iPhone XS/XR (2018)
        "iPhone11,8": CameraDeviceCameraSpec(ultraWideFocalLength: nil, wideFocalLength: 26, telephotoFocalLength: nil, deviceName: "iPhone XR"),
        "iPhone11,2": CameraDeviceCameraSpec(ultraWideFocalLength: nil, wideFocalLength: 26, telephotoFocalLength: 52, deviceName: "iPhone XS"),
        "iPhone11,6": CameraDeviceCameraSpec(ultraWideFocalLength: nil, wideFocalLength: 26, telephotoFocalLength: 52, deviceName: "iPhone XS Max"),

        // iPhone X (2017)
        "iPhone10,3": CameraDeviceCameraSpec(ultraWideFocalLength: nil, wideFocalLength: 28, telephotoFocalLength: 56, deviceName: "iPhone X"),
        "iPhone10,6": CameraDeviceCameraSpec(ultraWideFocalLength: nil, wideFocalLength: 28, telephotoFocalLength: 56, deviceName: "iPhone X"),

        // simulatorunknowndevice
        "arm64": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 77, deviceName: "iOS Simulator"),
        "x86_64": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 77, deviceName: "iOS Simulator"),
        "Unknown": CameraDeviceCameraSpec(ultraWideFocalLength: 13, wideFocalLength: 26, telephotoFocalLength: 77, deviceName: "Unknown iPhone"),
    ]

    /// get camera parameters for the current device
    static func getCurrentDeviceSpec() -> CameraDeviceCameraSpec {
        let modelIdentifier = getDeviceModelIdentifier()
        return specs[modelIdentifier] ?? specs["Unknown"]!
    }

    /// get the device model identifier
    private static func getDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String(validatingUTF8: ptr)
            }
        }
        return modelCode ?? "Unknown"
    }
}
