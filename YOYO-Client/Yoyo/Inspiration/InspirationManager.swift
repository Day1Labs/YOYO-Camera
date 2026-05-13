import Combine
import SwiftUI

// MARK: - inspiration manager

@MainActor
final class InspirationManager: ObservableObject {
    static let shared = InspirationManager()

    @Published private(set) var inspirations: [AIInspiration] = []
    @Published private(set) var historyInspirations: [AIInspiration] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var credits: Int = 0
    @Published var showLoginSheet: Bool = false
    @Published var showPaywall: Bool = false

    private var loadingIndices: Set<Int> = []
    private var originalImage: UIImage? // Store for lazy loading

    private var cancellables = Set<AnyCancellable>()

    private init() {
        AuthService.shared.$currentUser
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                self?.credits = user?.credits ?? 0
            }
            .store(in: &cancellables)

        loadHistory()
    }

    func requestAIInspirations(from image: UIImage?) async {
        guard AuthService.shared.isLoggedIn else {
            showLoginSheet = true
            return
        }

        if AuthService.shared.currentUser?.subscriptionStatus != 1 {
            showPaywall = true
            return
        }

        guard !isLoading else { return }

        // Check for credits (Pro users also have limits now)
        if credits < 1 {
            errorMessage = String.aiInspirationErrorInsufficientCredits.localized
            return
        }

        guard let image else {
            errorMessage = String.aiInspirationNoImage.localized
            return
        }

        originalImage = image // Keep reference
        isLoading = true
        errorMessage = nil

        do {
            let (results, remainingCredits) = try await AIInspirationService.shared.fetchInspirations(from: image)
            inspirations = results

            // Add to history
            addToHistory(results)

            // Update global credits
            AuthService.shared.updateCredits(remainingCredits)

            // 💡 Instantly trigger the generation of all inspiration maps in parallel
            for index in results.indices {
                Task {
                    await self.generateImage(for: index)
                }
            }
        } catch let error as AIInspirationServiceError {
            if case .insufficientCredits = error {
                errorMessage = String.aiInspirationErrorInsufficientCredits.localized
            } else {
                errorMessage = error.localizedDescription
            }
            inspirations = []
        } catch {
            errorMessage = String.aiInspirationGenerateFailed.localized
            inspirations = []
        }

        isLoading = false
    }

    func clearInspirations() {
        inspirations = []
        errorMessage = nil
        originalImage = nil
        loadingIndices.removeAll()
    }

    func generateImage(for index: Int) async {
        guard index >= 0, index < inspirations.count else { return }

        // Skip if already has image, no original image, or already loading
        guard inspirations[index].image == nil,
              let originalImage,
              !loadingIndices.contains(index) else { return }

        loadingIndices.insert(index)
        let inspiration = inspirations[index]

        do {
            let (image, remainingCredits) = try await AIInspirationService.shared.generateImage(for: inspiration, originalImage: originalImage)

            // Update on main thread
            await MainActor.run {
                self.loadingIndices.remove(index)

                // Update global credits
                AuthService.shared.updateCredits(remainingCredits)

                if index < self.inspirations.count {
                    // Update struct copy
                    var updatedInspiration = self.inspirations[index]
                    updatedInspiration.image = image
                    self.inspirations[index] = updatedInspiration

                    // Update in history as well
                    updateHistoryItem(updatedInspiration)
                }
            }
        } catch {
            print("Failed to generate lazy image: \(error)")
            await MainActor.run {
                self.loadingIndices.remove(index)
            }
        }
    }

    // MARK: - History Management

    private var historyDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("Inspirations", isDirectory: true)
    }

    private var imagesDirectory: URL {
        historyDirectory.appendingPathComponent("Images", isDirectory: true)
    }

    private var historyFile: URL {
        historyDirectory.appendingPathComponent("history.json")
    }

    private func ensureDirectoriesExist() {
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create history directories: \(error)")
        }
    }

    private func addToHistory(_ newInspirations: [AIInspiration]) {
        // Prepend to history
        historyInspirations.insert(contentsOf: newInspirations, at: 0)

        // Save images for those that have them (though usually new ones don't yet)
        for inspiration in newInspirations {
            if let image = inspiration.image {
                saveImage(image, for: inspiration.id)
            }
        }

        saveHistory()
    }

    private func updateHistoryItem(_ updatedInspiration: AIInspiration) {
        if let index = historyInspirations.firstIndex(where: { $0.id == updatedInspiration.id }) {
            historyInspirations[index] = updatedInspiration

            // Save image if updated
            if let image = updatedInspiration.image {
                saveImage(image, for: updatedInspiration.id)
            }

            saveHistory()
        }
    }

    func deleteHistoryItem(at indexSet: IndexSet) {
        for index in indexSet {
            let inspiration = historyInspirations[index]
            deleteImage(for: inspiration.id)
        }
        historyInspirations.remove(atOffsets: indexSet)
        saveHistory()
    }

    func clearHistory() {
        historyInspirations = []
        saveHistory()

        // Delete all images
        do {
            if FileManager.default.fileExists(atPath: imagesDirectory.path) {
                try FileManager.default.removeItem(at: imagesDirectory)
            }
            ensureDirectoriesExist()
        } catch {
            print("Failed to clear images directory: \(error)")
        }
    }

    private func saveHistory() {
        ensureDirectoriesExist()
        do {
            let data = try JSONEncoder().encode(historyInspirations)
            try data.write(to: historyFile)
        } catch {
            print("Failed to save history: \(error)")
        }
    }

    private func loadHistory() {
        ensureDirectoriesExist()
        do {
            guard FileManager.default.fileExists(atPath: historyFile.path) else { return }
            let data = try Data(contentsOf: historyFile)
            var loadedHistory = try JSONDecoder().decode([AIInspiration].self, from: data)

            // Load images from disk
            for i in 0 ..< loadedHistory.count {
                if let image = loadImage(for: loadedHistory[i].id) {
                    loadedHistory[i].image = image
                }
            }

            historyInspirations = loadedHistory
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func saveImage(_ image: UIImage, for id: UUID) {
        ensureDirectoriesExist()
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }

    private func loadImage(for id: UUID) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private func deleteImage(for id: UUID) {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }

    var isShowingInspirations: Bool {
        isLoading || !inspirations.isEmpty || errorMessage != nil
    }
}
