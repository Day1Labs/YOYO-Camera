import Combine
import Foundation
import SwiftUI

struct CustomFilter: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let lutFileName: String // The filename in the Documents/CustomLUTs directory
    var intensity: Float = 1.0
    var isFavorite: Bool = false
    let createdAt: Date

    init(id: UUID = UUID(), name: String, lutFileName: String, intensity: Float = 1.0, isFavorite: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.lutFileName = lutFileName
        self.intensity = intensity
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, lutFileName, intensity, isFavorite, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lutFileName = try container.decode(String.self, forKey: .lutFileName)
        intensity = try container.decode(Float.self, forKey: .intensity)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lutFileName, forKey: .lutFileName)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

final class CustomFilterManager: NSObject, ObservableObject {
    static let shared = CustomFilterManager()

    @Published var customFilters: [CustomFilter] = []

    private let fileManager = FileManager.default
    private let filtersFileName = "custom_filters.json"
    private let lutsDirectoryName = "CustomLUTs"

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var lutsDirectory: URL {
        documentsDirectory.appendingPathComponent(lutsDirectoryName)
    }

    private var filtersFileURL: URL {
        documentsDirectory.appendingPathComponent(filtersFileName)
    }

    override init() {
        super.init()
        createLutsDirectoryIfNeeded()
        loadFilters()
    }

    private func createLutsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: lutsDirectory.path) {
            try? fileManager.createDirectory(at: lutsDirectory, withIntermediateDirectories: true)
        }
    }

    func loadFilters() {
        guard fileManager.fileExists(atPath: filtersFileURL.path),
              let data = try? Data(contentsOf: filtersFileURL),
              let filters = try? JSONDecoder().decode([CustomFilter].self, from: data)
        else {
            return
        }
        customFilters = filters
    }

    func saveFilters() {
        if let data = try? JSONEncoder().encode(customFilters) {
            try? data.write(to: filtersFileURL)
        }
    }

    func importFilter(from url: URL) -> CustomFilter? {
        // Ensure we can access the file
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = url.lastPathComponent
        let destinationURL = lutsDirectory.appendingPathComponent(fileName)

        // If file already exists, generate a unique name
        var finalDestinationURL = destinationURL
        var finalFileName = fileName
        var counter = 1

        while fileManager.fileExists(atPath: finalDestinationURL.path) {
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            finalFileName = "\(nameWithoutExt)_\(counter).\(ext)"
            finalDestinationURL = lutsDirectory.appendingPathComponent(finalFileName)
            counter += 1
        }

        do {
            try fileManager.copyItem(at: url, to: finalDestinationURL)

            let filterName = (fileName as NSString).deletingPathExtension
            let newFilter = CustomFilter(name: filterName, lutFileName: finalFileName)

            DispatchQueue.main.async {
                self.customFilters.append(newFilter)
                self.saveFilters()
            }

            return newFilter
        } catch {
            print("Error importing filter: \(error)")
            return nil
        }
    }

    // MARK: - Remote Import

    enum RemoteImportError: Error, LocalizedError {
        case invalidURL
        case httpNotSupported
        case downloadFailed
        case badResponse
        case emptyData
        case unsupportedType
        case fileWriteFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String.filterImportErrorInvalidUrl.localized
            case .httpNotSupported:
                return String.filterImportErrorHttpNotSupported.localized
            case .downloadFailed:
                return String.filterImportErrorDownloadFailed.localized
            case .badResponse:
                return String.filterImportErrorBadResponse.localized
            case .emptyData:
                return String.filterImportErrorEmptyData.localized
            case .unsupportedType:
                return String.filterImportErrorUnsupportedType.localized
            case .fileWriteFailed:
                return String.filterImportErrorFileWriteFailed.localized
            }
        }
    }

    /// Download and import LUTs from remote addresses (supports .cube text)
    /// - Parameters:
    ///   - url: remote URL (only supports https)
    ///   - completion: completion callback, returns the newly created `CustomFilter`
    func importFilter(fromRemote url: URL, completion: @escaping (Result<CustomFilter, Error>) -> Void) {
        // Automatically complete scheme (for the case where the URL object scheme is empty)
        var targetURL = url
        if targetURL.scheme == nil {
            if let newURL = URL(string: "https://" + targetURL.absoluteString) {
                targetURL = newURL
            }
        }

        // Only supports https
        guard let scheme = targetURL.scheme?.lowercased() else {
            completion(.failure(RemoteImportError.invalidURL))
            return
        }

        guard scheme == "https" else {
            completion(.failure(RemoteImportError.httpNotSupported))
            return
        }

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30

        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let request = URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)

        let task = session.downloadTask(with: request) { tempURL, response, error in
            session.finishTasksAndInvalidate()

            if let error {
                completion(.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                completion(.failure(RemoteImportError.badResponse))
                return
            }

            guard let tempURL else {
                completion(.failure(RemoteImportError.downloadFailed))
                return
            }

            // Infer file name
            let suggestedName = Self.filename(from: http) ?? targetURL.lastPathComponent
            let safeName = suggestedName.isEmpty ? "LUT_\(UUID().uuidString).cube" : suggestedName
            let finalName = Self.ensureCubeExtension(for: safeName)

            // Read content to confirm type (best effort check)
            guard let data = try? Data(contentsOf: tempURL), !data.isEmpty else {
                completion(.failure(RemoteImportError.emptyData))
                return
            }

            // If not .cube, try to identify LUT_3D_SIZE in text to correct extension
            var destinationFileName = finalName
            if (finalName as NSString).pathExtension.lowercased() != "cube" {
                if let str = String(data: data, encoding: .utf8), str.contains("LUT_3D_SIZE") {
                    let nameWithoutExt = (finalName as NSString).deletingPathExtension
                    destinationFileName = nameWithoutExt + ".cube"
                } else {
                    // Currently only .cube is supported
                    completion(.failure(RemoteImportError.unsupportedType))
                    return
                }
            }

            // Generate unique file name
            let (destURL, uniqueFileName) = self.uniqueDestination(for: destinationFileName)

            do {
                // Copy the downloaded temporary file to the target location
                if self.fileManager.fileExists(atPath: destURL.path) {
                    try self.fileManager.removeItem(at: destURL)
                }
                try self.fileManager.copyItem(at: tempURL, to: destURL)

                let filterName = (uniqueFileName as NSString).deletingPathExtension
                let newFilter = CustomFilter(name: filterName, lutFileName: uniqueFileName)

                DispatchQueue.main.async {
                    self.customFilters.append(newFilter)
                    self.saveFilters()
                    completion(.success(newFilter))
                }
            } catch {
                completion(.failure(RemoteImportError.fileWriteFailed))
            }
        }

        task.resume()
    }

    /// Convenience method wrapped from a string URL
    func importFilter(fromRemote urlString: String, completion: @escaping (Result<CustomFilter, Error>) -> Void) {
        var formattedString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !formattedString.lowercased().hasPrefix("http://"), !formattedString.lowercased().hasPrefix("https://") {
            formattedString = "https://" + formattedString
        }

        guard let url = URL(string: formattedString) else {
            completion(.failure(RemoteImportError.invalidURL))
            return
        }
        importFilter(fromRemote: url, completion: completion)
    }

    // MARK: - Helpers

    private static func filename(from http: HTTPURLResponse) -> String? {
        // Parse the filename of Content-Disposition
        if let disposition = http.allHeaderFields["Content-Disposition"] as? String {
            // In the form: attachment; filename="foo.cube"
            if let range = disposition.range(of: "filename=") {
                var value = String(disposition[range.upperBound...])
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                // Remove additional fields after semicolon
                if let semi = value.firstIndex(of: ";") {
                    value = String(value[..<semi])
                }
                return value.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func ensureCubeExtension(for name: String) -> String {
        let ext = (name as NSString).pathExtension
        if ext.isEmpty { return name + ".cube" }
        if ext.lowercased() == "cube" { return name }
        return name
    }

    private func uniqueDestination(for fileName: String) -> (URL, String) {
        var finalDestinationURL = lutsDirectory.appendingPathComponent(fileName)
        var finalFileName = fileName
        var counter = 1
        while fileManager.fileExists(atPath: finalDestinationURL.path) {
            let nameWithoutExt = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            finalFileName = "\(nameWithoutExt)_\(counter).\(ext.isEmpty ? "cube" : ext)"
            finalDestinationURL = lutsDirectory.appendingPathComponent(finalFileName)
            counter += 1
        }
        return (finalDestinationURL, finalFileName)
    }

    func deleteFilter(_ filter: CustomFilter) {
        if let index = customFilters.firstIndex(of: filter) {
            let lutURL = lutsDirectory.appendingPathComponent(filter.lutFileName)
            try? fileManager.removeItem(at: lutURL)

            customFilters.remove(at: index)
            saveFilters()
        }
    }

    func toggleFavorite(_ filter: CustomFilter) {
        if let index = customFilters.firstIndex(where: { $0.id == filter.id }) {
            customFilters[index].isFavorite.toggle()
            saveFilters()
        }
    }

    func getLutData(for filter: CustomFilter) -> (Data?, Int) {
        let lutURL = lutsDirectory.appendingPathComponent(filter.lutFileName)
        guard let data = try? Data(contentsOf: lutURL) else {
            return (nil, 0)
        }

        // Parse size from data if possible, similar to FilterManager
        // For now, default to 33 or try to parse
        var size = 33
        if let cubeString = String(data: data, encoding: .utf8) {
            if let sizeLine = cubeString.components(separatedBy: .newlines).first(where: { $0.contains("LUT_3D_SIZE") }) {
                let comps = sizeLine.components(separatedBy: .whitespaces).compactMap { Int($0) }
                size = comps.last ?? 33
            }
        }

        return (data, size)
    }
}

extension CustomFilterManager: URLSessionDelegate {
    func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
