import Foundation

// MARK: - file type enum
enum FileType {
    case photo
    case video
    case livePhoto

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .livePhoto: return "LivePhoto"
        }
    }
}

// MARK: - File format enumeration
enum FileFormat {
    case jpg
    case heic
    case mp4
    case mov
    case dng

    var fileExtension: String {
        switch self {
        case .jpg: return "jpg"
        case .heic: return "heic"
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .dng: return "dng"
        }
    }

    var displayName: String {
        switch self {
        case .jpg: return "JPG"
        case .heic: return "HEIC"
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .dng: return "RAW"
        }
    }
}

// MARK: - counter
final class FileNameCounter {
    private var globalIndex: Int = 0
    private let queue = DispatchQueue(label: "com.day1-labs.yoyo.filenamecounter", attributes: .concurrent)
    private let storageKey = "FileNameCounter.GlobalIndex"

    init() {
        // Read the persisted global index.
        let savedIndex = UserDefaults.standard.integer(forKey: storageKey)
        globalIndex = savedIndex
    }

    /// Get the next global sequence number.
    func getNextIndex() -> Int {
        queue.sync(flags: .barrier) {
            globalIndex += 1
            if globalIndex > 9999 {
                globalIndex = 1 // Loop after more than 4 digits.
            }
            save()
            return globalIndex
        }
    }

    /// Reset the serial number.
    func resetIndex() {
        queue.sync(flags: .barrier) {
            globalIndex = 0
            save()
        }
    }

    private func save() {
        UserDefaults.standard.set(globalIndex, forKey: storageKey)
    }
}

// MARK: - filename generator
final class FileNameGenerator {
    // MARK: - Singleton
    static let shared = FileNameGenerator()

    // MARK: - formatter
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let timestampFormatter: DateFormatter
    private let counter: FileNameCounter

    private init() {
        // Date formatter: 2024-10-29.
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Time formatter: 14-30-22.
        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"

        // Timestamp formatter: 20241029143022.
        timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMddHHmmss"

        // Initialize counter.
        counter = FileNameCounter()
    }

    // MARK: - public method
    /// Generate a file name without its extension.
    func generateFileName(
        template: String,
        prefix: String,
        fileType: FileType,
        fileFormat: FileFormat,
        date: Date = Date()
    ) -> String {
        let variables = createVariables(
            prefix: prefix,
            fileType: fileType,
            fileFormat: fileFormat,
            date: date
        )

        return replaceVariables(in: template, with: variables)
    }

    /// Generate a full filename including the extension.
    func generateFullFileName(
        template: String,
        prefix: String,
        fileType: FileType,
        fileFormat: FileFormat,
        date: Date = Date(),
        isOriginal: Bool = false
    ) -> String {
        let baseName = generateFileName(
            template: template,
            prefix: prefix,
            fileType: fileType,
            fileFormat: fileFormat,
            date: date
        )

        let finalBaseName = isOriginal ? "\(baseName)_original" : baseName
        return "\(finalBaseName).\(fileFormat.fileExtension)"
    }

    /// Generate paired filenames for Live Photos.
    func generateLivePhotoFileNames(
        template: String,
        prefix: String,
        fileFormat: FileFormat,
        date: Date = Date()
    ) -> (imageFileName: String, videoFileName: String) {
        let imageBaseName = generateFileName(
            template: template,
            prefix: prefix,
            fileType: .livePhoto,
            fileFormat: fileFormat,
            date: date
        )

        let videoBaseName = generateFileName(
            template: template,
            prefix: prefix,
            fileType: .livePhoto,
            fileFormat: .mov, // Live Photo videos are always in MOV format.
            date: date
        )

        return (
            "\(imageBaseName).\(fileFormat.fileExtension)",
            "\(videoBaseName).mov"
        )
    }

    // MARK: - private method
    /// Create the variable dictionary used in the template.
    private func createVariables(
        prefix: String,
        fileType: FileType,
        fileFormat: FileFormat,
        date: Date
    ) -> [String: String] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let dateString = dateFormatter.string(from: date)
        let timeString = timeFormatter.string(from: date)
        let timestampString = timestampFormatter.string(from: date)

        // Generate a short UUID (first 4 digits).
        let shortUUID = UUID().uuidString.prefix(4)

        // Get the global serial number.
        let index = counter.getNextIndex()

        return [
            "{prefix}": prefix,
            "{timestamp}": timestampString,
            "{date}": dateString,
            "{time}": timeString,
            "{year}": String(components.year ?? 0),
            "{month}": String(format: "%02d", components.month ?? 0),
            "{day}": String(format: "%02d", components.day ?? 0),
            "{hour}": String(format: "%02d", components.hour ?? 0),
            "{minute}": String(format: "%02d", components.minute ?? 0),
            "{second}": String(format: "%02d", components.second ?? 0),
            "{type}": fileType.displayName,
            "{format}": fileFormat.displayName,
            "{uuid}": String(shortUUID),
            "{index}": String(format: "%04d", index),
        ]
    }

    /// Replace variables in the template.
    private func replaceVariables(in template: String, with variables: [String: String]) -> String {
        var result = template

        for (key, value) in variables {
            result = result.replacingOccurrences(of: key, with: value)
        }

        // Clean illegal characters in file names.
        return sanitizeFileName(result)
    }

    /// Remove illegal filename characters.
    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:*?\"<>|")
        return fileName.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}

// MARK: - Extension: Preview function
extension FileNameGenerator {
    /// Preview a filename without incrementing the stored counter.
    func previewFileName(
        template: String,
        prefix: String,
        fileType: FileType,
        fileFormat: FileFormat,
        date: Date = Date(),
        sampleIndex: Int = 1
    ) -> String {
        let variables = createVariablesForPreview(
            prefix: prefix,
            fileType: fileType,
            fileFormat: fileFormat,
            date: date,
            sampleIndex: sampleIndex
        )

        return replaceVariables(in: template, with: variables)
    }

    /// Create the variable dictionary for previews without using the real counter.
    private func createVariablesForPreview(
        prefix: String,
        fileType: FileType,
        fileFormat: FileFormat,
        date: Date,
        sampleIndex: Int
    ) -> [String: String] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let dateString = dateFormatter.string(from: date)
        let timeString = timeFormatter.string(from: date)
        let timestampString = timestampFormatter.string(from: date)

        // Use a fixed sample UUID for previews.
        let shortUUID = "A1B2"

        return [
            "{prefix}": prefix,
            "{timestamp}": timestampString,
            "{date}": dateString,
            "{time}": timeString,
            "{year}": String(components.year ?? 0),
            "{month}": String(format: "%02d", components.month ?? 0),
            "{day}": String(format: "%02d", components.day ?? 0),
            "{hour}": String(format: "%02d", components.hour ?? 0),
            "{minute}": String(format: "%02d", components.minute ?? 0),
            "{second}": String(format: "%02d", components.second ?? 0),
            "{type}": fileType.displayName,
            "{format}": fileFormat.displayName,
            "{uuid}": shortUUID,
            "{index}": String(format: "%04d", sampleIndex),
        ]
    }
}
