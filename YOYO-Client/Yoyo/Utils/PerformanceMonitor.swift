import Foundation

/// performance monitor - used foroperation
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private var timers: [String: CFAbsoluteTime] = [:]
    private let queue = DispatchQueue(label: "performance.monitor", attributes: .concurrent)

    private init() {}

    /// start
    func startTimer(_ name: String) {
        queue.async(flags: .barrier) {
            self.timers[name] = CFAbsoluteTimeGetCurrent()
        }
        print("⏱️ [Performance] Started timer: \(name)")
    }

    /// endand
    @discardableResult
    func endTimer(_ name: String) -> TimeInterval {
        let endTime = CFAbsoluteTimeGetCurrent()

        return queue.sync {
            guard let startTime = timers[name] else {
                print("⚠️ [Performance] Timer '\(name)' not found")
                return 0
            }

            let elapsed = endTime - startTime
            timers.removeValue(forKey: name)

            print("⏱️ [Performance] \(name): \(String(format: "%.3f", elapsed))s")
            return elapsed
        }
    }

    /// Measure execution time for a code block
    func measure<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
        startTimer(name)
        defer { endTimer(name) }
        return try await operation()
    }

    /// sync
    func measureSync<T>(_ name: String, operation: () throws -> T) rethrows -> T {
        startTimer(name)
        defer { endTimer(name) }
        return try operation()
    }
}

/// performance monitoring - operationmethod
extension PerformanceMonitor {
    /// Live Photo save
    func monitorLivePhotoSave<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await measure("LivePhoto_Save_Total", operation: operation)
    }

    /// videofilter
    func monitorVideoFilter<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await measure("Video_Filter_Processing", operation: operation)
    }

    /// imagegenerate
    func monitorImageGeneration<T>(_ operation: () throws -> T) rethrows -> T {
        try measureSync("Image_Generation", operation: operation)
    }

    /// photo librarysave
    func monitorAlbumSave<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await measure("Album_Save", operation: operation)
    }
}
