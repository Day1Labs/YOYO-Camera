import Foundation

extension FileManager {
    /// createtemporaryvideoURL
    static func createTempVideoURL(prefix: String = "VIDEO") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).mov"
        return tempDir.appendingPathComponent(fileName)
    }

    /// createtemporarymovieURL(used forfilter)
    static func createTempMovieURL(prefix: String = "MOVIE") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).mov"
        return tempDir.appendingPathComponent(fileName)
    }

    /// createtemporaryLive PhotovideoURL
    static func createTempLivePhotoVideoURL(prefix: String = "LIVEPHOTO") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).mov"
        return tempDir.appendingPathComponent(fileName)
    }

    /// Safely delete a file
    static func safeRemoveItem(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("🗑️ [FileManager] Removed file: \(url.lastPathComponent)")
            } else {
                print("⚠️ [FileManager] File not found, skip removal: \(url.lastPathComponent)")
            }
        } catch {
            print("❌ [FileManager] Failed to remove file \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// (and)
    static func safeRemoveItems(at urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    safeRemoveItem(at: url)
                }
            }
        }
    }

    /// delay(used forin progressuse)
    static func delayedRemoveItem(at url: URL, delay: TimeInterval = 1.0) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            safeRemoveItem(at: url)
        }
    }

    /// validatewhether
    static func validateFile(at url: URL, minSize: Int64 = 1024) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            return fileSize >= minSize
        } catch {
            return false
        }
    }
}
