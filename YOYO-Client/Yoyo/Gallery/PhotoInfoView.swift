import CoreLocation
import Photos
import SwiftUI

// MARK: - PhotoInfoView

struct PhotoInfoView: View {
    var photo: PhotoAsset?
    @Environment(\.dismiss) private var dismiss
    @State private var photoInfo = PhotoInfoData()
    @State private var isCalculatingScore = false
    @State private var calculatedScore: Float?
    @State private var isGeocoding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top area: date and time + adjustment buttons.
            headerSection

            // Device information card.
            deviceInfoCard
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        .trackScreen(name: "PhotoInfo")
        .task {
            await loadPhotoInfo()
            await calculateAestheticsScoreIfNeeded()
        }
    }

    // MARK: - top area
    /// Icon used for the current file type.
    private var filenameIcon: String {
        if photoInfo.mediaSubtypes.contains(.photoLive) {
            return "livephoto"
        } else if photoInfo.mediaType == .video {
            return "video"
        } else {
            return "photo"
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Date and time.
            VStack(alignment: .leading, spacing: 0) {
                if let timestamp = photo?.timestamp {
                    Text(formatDateLine(timestamp))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }

            // File name.
            if let filename = photoInfo.filename {
                HStack(spacing: 4) {
                    Image(systemName: filenameIcon)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(filename)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Device information card
    private var deviceInfoCard: some View {
        GlassCard(paddingValue: 16) {
            VStack(alignment: .leading, spacing: 0) {
                // First line: device name + format label.
                HStack {
                    Text(photoInfo.deviceName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if let format = photoInfo.fileFormat {
                        Text(format)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                }
                .padding(.bottom, 4)

                // Second line: lens information.
                if let lensInfo = photoInfo.lensInfoLine {
                    Text(lensInfo)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                // Third line: pixels, resolution, file size, and tags.
                HStack {
                    Text(photoInfo.resolutionLine)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let filterName = photo?.filterIdentifier {
                        Text(FilterConfigManager.getFilterDisplayName(for: filterName))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(.bottom, 12)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Shooting parameter line.
                shootingParametersRow
                    .padding(.vertical, 10)

                // Aesthetic score.
                if let score = calculatedScore ?? photo?.aestheticsScore {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    aestheticsScoreRow(score: score)
                        .padding(.vertical, 8)
                } else if isCalculatingScore {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    HStack {
                        Text(String.photoInfoAestheticsScore.localized)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    .padding(.vertical, 8)
                }

                // Additional information such as brightness, white balance, and color space.
                if photoInfo.hasExtraInfo {
                    Divider()
                        .background(Color.white.opacity(0.1))
                    extraInfoSection
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Shooting parameter line
    private var shootingParametersRow: some View {
        HStack(spacing: 0) {
            if photoInfo.mediaType == .video {
                // FPS
                parameterItem(value: photoInfo.fps ?? "-")

                parameterDivider

                // Video duration.
                parameterItem(value: photoInfo.duration ?? "-")
            } else {
                // ISO
                parameterItem(value: photoInfo.iso ?? "-")

                parameterDivider

                // Focal length.
                parameterItem(value: photoInfo.focalLength ?? "-")

                parameterDivider

                // Exposure compensation.
                parameterItem(value: photoInfo.exposureBias ?? "0 ev")

                parameterDivider

                // Aperture.
                parameterItem(value: photoInfo.aperture ?? "-")

                parameterDivider

                // Shutter speed.
                parameterItem(value: photoInfo.shutterSpeed ?? "-")
            }
        }
    }

    private func parameterItem(value: String) -> some View {
        Text(value)
            .font(.system(size: 14))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
    }

    private var parameterDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 16)
    }

    // MARK: - aesthetic rating line
    private func aestheticsScoreRow(score: Float) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(String.photoInfoAestheticsScore.localized)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(String(format: "%.1f", score))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Additional information section
    private var extraInfoSection: some View {
        VStack(spacing: 6) {
            if let locationName = photoInfo.locationName {
                extraInfoRow(
                    label: String.frameSettingsLocation.localized,
                    value: locationName
                )
            } else if let location = photoInfo.location {
                extraInfoRow(
                    label: String.frameSettingsLocation.localized,
                    value: "\(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude))"
                )
            }
            if let brightness = photoInfo.brightness {
                extraInfoRow(label: String.photoInfoBrightness.localized, value: brightness)
            }
            if let whiteBalance = photoInfo.whiteBalance {
                extraInfoRow(label: String.photoInfoWhiteBalance.localized, value: whiteBalance)
            }
            if let flash = photoInfo.flash {
                extraInfoRow(label: String.photoInfoFlash.localized, value: flash)
            }
            if let colorSpace = photoInfo.colorSpace {
                extraInfoRow(label: String.photoInfoColorSpace.localized, value: colorSpace)
            }
            if let colorDepth = photoInfo.colorDepth {
                extraInfoRow(label: String.photoInfoColorDepth.localized, value: colorDepth)
            }
        }
    }

    private func extraInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
    }

    // MARK: - date formatting
    private func formatDateLine(_ date: Date) -> String {
        let locale = LanguageManager.shared.locale
        // Support internationalization using Swift native FormatStyle.
        return date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .weekday(.wide)
                .hour()
                .minute()
                .locale(locale)
        )
    }

    private func calculateAestheticsScoreIfNeeded() async {
        guard let photo, photo.aestheticsScore == nil else { return }

        await MainActor.run {
            isCalculatingScore = true
        }

        do {
            if #available(iOS 18.0, *) {
                let score = try await AestheticsScoreManager.calculateAndSaveScore(for: photo)

                await MainActor.run {
                    calculatedScore = score
                    isCalculatingScore = false
                }
            } else {
                await MainActor.run {
                    isCalculatingScore = false
                }
            }
        } catch {
            print("计算图片美学评分失败: \(error.localizedDescription)")
            await MainActor.run {
                isCalculatingScore = false
            }
        }
    }

    // MARK: - Load photo information
    private func loadPhotoInfo() async {
        guard let photo else { return }
        guard UIApplication.shared.applicationState == .active else { return }

        var info = PhotoInfoData()

        // Get information from PHAsset.
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.assetIdentifier], options: nil)
        if let asset = fetchResult.firstObject {
            info.mediaType = asset.mediaType
            info.mediaSubtypes = asset.mediaSubtypes
            info.location = asset.location

            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first {
                // File name.
                let filename = resource.originalFilename
                info.filename = (filename as NSString).deletingPathExtension

                // File format.
                let ext = (filename as NSString).pathExtension.uppercased()
                info.fileFormat = ext == "HEIC" ? "HEIF" : ext

                // File size.
                if let fileSize = resource.value(forKey: "fileSize") as? Int {
                    info.fileSize = formatFileSize(fileSize)
                }
            }

            // Image size.
            let pixelWidth = asset.pixelWidth
            let pixelHeight = asset.pixelHeight
            if pixelWidth > 0, pixelHeight > 0 {
                info.width = pixelWidth
                info.height = pixelHeight

                // Calculate megapixels.
                let megapixels = Double(pixelWidth * pixelHeight) / 1_000_000.0
                info.megapixels = String(format: "%.0f MP", megapixels)
            }

            // Video information.
            if asset.mediaType == .video {
                info.duration = formatDuration(asset.duration)

                // Get FPS.
                let options = PHVideoRequestOptions()
                options.version = .current
                options.deliveryMode = .fastFormat
                options.isNetworkAccessAllowed = true

                let avAsset = await withCheckedContinuation { continuation in
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                        continuation.resume(returning: avAsset)
                    }
                }

                if let avAsset {
                    if #available(iOS 16.0, *) {
                        if let track = try? await avAsset.loadTracks(withMediaType: .video).first {
                            if let nominalFrameRate = try? await track.load(.nominalFrameRate) {
                                let fps = Int(round(nominalFrameRate))
                                info.fps = "\(fps) FPS"
                            }
                        }
                    } else {
                        if let track = avAsset.tracks(withMediaType: .video).first {
                            let fps = Int(round(track.nominalFrameRate))
                            info.fps = "\(fps) FPS"
                        }
                    }
                }
            }
        }

        // Extract EXIF information from metadata.
        if let metadataDict = photo.metadataDict {
            // Extract location name.
            if let locationName = metadataDict["locationName"] as? String {
                info.locationName = locationName
            }

            // Extract TIFF information (device name).
            if let tiffDict = metadataDict["{TIFF}"] as? [String: Any] {
                var deviceParts: [String] = []
                if let make = tiffDict["Make"] as? String {
                    deviceParts.append(make)
                }
                if let model = tiffDict["Model"] as? String {
                    deviceParts.append(model)
                }
                if !deviceParts.isEmpty {
                    info.deviceName = deviceParts.joined(separator: " ")
                }
            }

            // Extract EXIF information.
            if let exifDict = metadataDict["{Exif}"] as? [String: Any] {
                // Aperture.
                if let fNumber = exifDict["FNumber"] as? Double {
                    info.aperture = "ƒ\(String(format: "%.2f", fNumber))"
                    info.apertureValue = fNumber
                }

                // Shutter speed.
                if let exposureTime = exifDict["ExposureTime"] as? Double {
                    if exposureTime >= 1 {
                        info.shutterSpeed = "\(Int(exposureTime)) s"
                    } else {
                        info.shutterSpeed = "1/\(Int(1 / exposureTime)) s"
                    }
                }

                // ISO
                if let iso = exifDict["ISOSpeedRatings"] as? [Int], let isoValue = iso.first {
                    info.iso = "ISO \(isoValue)"
                }

                // Original focal length, used by `lensInfoLine`.
                if let focalLength = exifDict["FocalLength"] as? Double {
                    info.focalLengthValue = Int(focalLength)
                }

                // 35mm equivalent focal length for shooting parameter display.
                if let focalLength35mm = exifDict["FocalLenIn35mmFilm"] as? Int {
                    info.focalLength35mm = focalLength35mm
                    info.focalLength = "\(focalLength35mm) mm"
                } else if let focalLength = exifDict["FocalLength"] as? Double {
                    // Fall back to original focal length if 35mm equivalent is unavailable.
                    info.focalLength = "\(Int(focalLength)) mm"
                }

                // Exposure compensation.
                if let exposureBias = exifDict["ExposureBiasValue"] as? Double {
                    let sign = exposureBias >= 0 ? "+" : ""
                    info.exposureBias = "\(sign)\(String(format: "%.0f", exposureBias)) ev"
                } else {
                    info.exposureBias = "0 ev"
                }

                // Lens information.
                if let lensModel = exifDict["LensModel"] as? String {
                    info.lensModel = lensModel
                }

                // Brightness value.
                if let brightnessValue = exifDict["BrightnessValue"] as? Double {
                    info.brightness = String(format: "%.1f EV", brightnessValue)
                }

                // White balance.
                if let whiteBalance = exifDict["WhiteBalance"] as? Int {
                    info.whiteBalance = whiteBalance == 0 ? "Auto" : "Manual"
                }

                // Flash.
                if let flash = exifDict["Flash"] as? Int {
                    info.flash = (flash & 0x01) != 0 ? String.commonOn.localized : String.commonOff.localized
                }

                // Color space.
                if let colorSpace = exifDict["ColorSpace"] as? Int {
                    switch colorSpace {
                    case 1:
                        info.colorSpace = info.mediaType == .video ? "Rec. 709" : "sRGB"
                    case 2:
                        info.colorSpace = "Adobe RGB"
                    case 65535, -3:
                        info.colorSpace = "Display P3"
                    case -1:
                        info.colorSpace = "Rec. 2020"
                    default:
                        info.colorSpace = "Other"
                    }
                }
            }

            // Color depth obtained directly from PHAsset.
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.assetIdentifier], options: nil)
            if let asset = fetchResult.firstObject {
                let options = PHImageRequestOptions()
                options.isSynchronous = true
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = false

                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    if let data, let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
                           let depth = properties[kCGImagePropertyDepth as String] as? Int
                        {
                            info.colorDepth = "\(depth) bit"
                        } else if let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                            let bitsPerComponent = cgImage.bitsPerComponent
                            if bitsPerComponent > 0 {
                                info.colorDepth = "\(bitsPerComponent) bit"
                            }
                        }
                    }
                }
            }
        }

        await MainActor.run {
            photoInfo = info
        }

        // If coordinates exist but the location name is missing, try reverse geocoding.
        if let location = info.location, info.locationName == nil {
            await reverseGeocode(location)
        }
    }

    private func reverseGeocode(_: CLLocation) async {
        guard !isGeocoding else { return }

        await MainActor.run { isGeocoding = true }

        if let photo {
            await photo.enrichLocationNameIfNeeded()
            // Update local UI-bound data.
            if let name = photo.metadataDict?["locationName"] as? String {
                await MainActor.run {
                    photoInfo.locationName = name
                }
            }
        }

        await MainActor.run { isGeocoding = false }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - PhotoInfoData

struct PhotoInfoData {
    var filename: String?
    var fileFormat: String?
    var fileSize: String?
    var width: Int = 0
    var height: Int = 0
    var megapixels: String?

    var mediaType: PHAssetMediaType = .image
    var mediaSubtypes: PHAssetMediaSubtype = []

    var deviceName: String = .commonUnknown.localized
    var lensModel: String?
    var focalLengthValue: Int?
    var focalLength35mm: Int?
    var apertureValue: Double?

    var iso: String?
    var focalLength: String?
    var exposureBias: String?
    var aperture: String?
    var shutterSpeed: String?

    var fps: String?
    var duration: String?

    var location: CLLocation?
    var locationName: String?

    // Additional information.
    var brightness: String?
    var whiteBalance: String?
    var flash: String?
    var colorSpace: String?
    var colorDepth: String?

    /// Lens information line, for example: "Main camera - 24 mm ƒ 1.78".
    var lensInfoLine: String? {
        var parts: [String] = []
        // Prefer 35mm equivalent focal length, otherwise use the original focal length.
        if let focal35mm = focalLength35mm {
            parts.append("\(focal35mm) mm")
        } else if let focal = focalLengthValue {
            parts.append("\(focal) mm")
        }
        if let aperture = apertureValue {
            parts.append("ƒ\(String(format: "%.2f", aperture))")
        }

        guard !parts.isEmpty else { return nil }

        let cameraName = cameraDisplayName
        return "\(cameraName) — \(parts.joined(separator: " "))"
    }

    private var cameraDisplayName: String {
        // 1. Prefer inferring from the `lensModel` keyword.
        if let lens = lensModel?.lowercased() {
            if lens.contains("ultra wide") {
                return String.photoInfoUltraWideCamera.localized
            }
            if lens.contains("telephoto") {
                return String.photoInfoTelephotoCamera.localized
            }
            // Some devices may indicate "wide" as the main camera.
            if lens.contains("wide"), !lens.contains("ultra") {
                return String.photoInfoMainCamera.localized
            }
        }

        // 2. Infer from 35mm equivalent focal length.
        if let focal35mm = focalLength35mm {
            if focal35mm <= 20 {
                return String.photoInfoUltraWideCamera.localized
            } else if focal35mm >= 45 {
                return String.photoInfoTelephotoCamera.localized
            } else {
                return String.photoInfoMainCamera.localized
            }
        }

        // 3. Infer from the original focal length as a fallback.
        if let focal = focalLengthValue {
            if focal < 4 {
                return String.photoInfoUltraWideCamera.localized
            } else if focal >= 10 {
                return String.photoInfoTelephotoCamera.localized
            }
        }

        return String.photoInfoMainCamera.localized
    }

    /// Resolution row, for example: "24 MP · 4284 x 5712 · 3 MB".
    var resolutionLine: String {
        var parts: [String] = []
        if let mp = megapixels {
            parts.append(mp)
        }
        if width > 0, height > 0 {
            parts.append("\(width) × \(height)")
        }
        if let size = fileSize {
            parts.append(size)
        }
        return parts.joined(separator: " · ")
    }

    /// Whether extra information exists.
    var hasExtraInfo: Bool {
        location != nil || brightness != nil || whiteBalance != nil || flash != nil || colorSpace != nil || colorDepth != nil
    }
}

#Preview {
    @Previewable @State var samplePhoto: PhotoAsset = {
        let photo = PhotoAsset(
            previewAssetIdentifier: "preview_sample_photo",
            title: "Sample Photo"
        )
        photo.aestheticsScore = 8.5
        photo.timestamp = Date()
        photo.filterName = "Alpine"

        // Add simulated EXIF metadata.
        let metadataDict: [String: Any] = [
            "{Exif}": [
                "FNumber": 1.78,
                "ExposureTime": 1.0 / 60.0,
                "ISOSpeedRatings": [400],
                "FocalLength": 24.0,
                "FocalLenIn35mmFilm": 24,
                "ExposureBiasValue": 0.0,
                "WhiteBalance": 0,
                "Flash": 0,
                "ColorSpace": 1,
                "LensModel": "iPhone 17 Pro back camera 24mm f/1.78",
            ],
            "{TIFF}": [
                "Make": "Apple",
                "Model": "iPhone 17 Pro",
            ],
        ]
        photo.metadata = DictionarySerializer.encodeDictionaryToData(metadataDict)
        return photo
    }()

    PhotoInfoView(photo: samplePhoto)
        .modelContainer(for: PhotoAsset.self, inMemory: true)
        .preferredColorScheme(.dark)
}
