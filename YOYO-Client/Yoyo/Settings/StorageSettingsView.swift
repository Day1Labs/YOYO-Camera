import SwiftUI

struct StorageSettingsView: View {
    @State private var totalSpace: Int64 = 0
    @State private var freeSpace: Int64 = 0
    @State private var appSize: Int64 = 0
    @State private var documentsSize: Int64 = 0
    @State private var librarySize: Int64 = 0
    @State private var cacheSize: Int64 = 0
    @State private var tempSize: Int64 = 0
    @State private var isClearing = false
    @State private var showClearAlert = false
    @AppStorage("isDeveloperMode") private var isDeveloperMode: Bool = false

    private var documentsURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private var libraryURL: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private var tempURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Device storage
                storageSection(
                    title: String.settingsStorageDevice.localized,
                    rows: [
                        (String.settingsStorageTotal.localized, formatBytes(totalSpace)),
                        (String.settingsStorageAvailable.localized, formatBytes(freeSpace)),
                    ]
                )

                // MARK: - App storage
                VStack(alignment: .leading, spacing: 8) {
                    Text(String.settingsStorageApp.localized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.gray)
                        .padding(.leading, 4)

                    GlassCard(paddingValue: 0) {
                        VStack(spacing: 0) {
                            storageRow(title: String.settingsStorageAppUsage.localized, value: formatBytes(appSize))

                            Divider().background(Color.white.opacity(0.1))
                                .padding(.leading, 20)

                            if let docsURL = documentsURL {
                                NavigationLink(destination: StorageDetailView(title: String.settingsStorageDocuments.localized, url: docsURL)) {
                                    storageRow(title: String.settingsStorageDocuments.localized, value: formatBytes(documentsSize), isLink: isDeveloperMode && documentsSize > 0)
                                }
                                .disabled(!isDeveloperMode || documentsSize == 0)
                            }

                            Divider().background(Color.white.opacity(0.1))
                                .padding(.leading, 20)

                            if let libURL = libraryURL {
                                NavigationLink(destination: StorageDetailView(title: String.settingsStorageLibrary.localized, url: libURL)) {
                                    storageRow(title: String.settingsStorageLibrary.localized, value: formatBytes(librarySize), isLink: isDeveloperMode && librarySize > 0)
                                }
                                .disabled(!isDeveloperMode || librarySize == 0)
                            }

                            Divider().background(Color.white.opacity(0.1))
                                .padding(.leading, 20)

                            if let cacheURL {
                                NavigationLink(destination: StorageDetailView(title: String.settingsStorageCache.localized, urls: [cacheURL, tempURL])) {
                                    storageRow(title: String.settingsStorageCache.localized, value: formatBytes(cacheSize), isLink: isDeveloperMode && cacheSize > 0)
                                }
                                .disabled(!isDeveloperMode || cacheSize == 0)
                            }
                        }
                    }
                }

                // MARK: - operate
                actionSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(white: 0.04).ignoresSafeArea())
        .navigationTitle(String.settingsStorageManagement.localized)
        .navigationBarTitleDisplayMode(.inline)
        .buttonStyle(.plain)
        .trackScreen(name: "StorageSettings")
        .onAppear {
            loadStorageInfo()
        }
        .alert(String.settingsStorageClearCache.localized, isPresented: $showClearAlert) {
            Button(String.commonCancel.localized, role: .cancel) {}
            Button(String.settingsStorageClear.localized, role: .destructive) {
                AnalyticsManager.shared.log(.settingsAction(action: "clear_cache"))
                clearCache()
            }
        } message: {
            Text(String.settingsStorageClearConfirm.localized(formatBytes(cacheSize)))
        }
    }

    // MARK: - view component
    private func storageSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            GlassCard(paddingValue: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider()
                                .background(Color.white.opacity(0.1))
                                .padding(.leading, 20)
                        }
                        storageRow(title: row.0, value: row.1)
                    }
                }
            }
        }
    }

    private func storageRow(title: String, value: String, isLink: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.gray)
            if isLink {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String.settingsStorageActions.localized)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            Button {
                showClearAlert = true
            } label: {
                HStack {
                    Text(String.settingsStorageClearCache.localized)
                        .font(.system(size: 16))
                        .foregroundStyle(cacheSize > 0 ? .red : .gray)
                    Spacer()
                    if isClearing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .disabled(cacheSize == 0 || isClearing)
            .glassCardStyle()
        }
    }

    // MARK: - Data loading
    private func loadStorageInfo() {
        // Device storage.
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            totalSpace = Int64(values.volumeTotalCapacity ?? 0)
            freeSpace = Int64(values.volumeAvailableCapacity ?? 0)
        }

        // App usage (asynchronous calculation).
        Task {
            let docs = await calculateDirectorySize(directory: .documentDirectory)
            let lib = await calculateDirectorySize(directory: .libraryDirectory)
            let tmp = await calculateTmpSize()
            let cache = await calculateCacheSize()

            await MainActor.run {
                documentsSize = docs
                librarySize = max(0, lib - cache) // Library excludes Caches and is shown as an independent category.
                cacheSize = cache + tmp // Cache size includes system cache and temporary files.
                tempSize = tmp
                // App usage includes documents, library, and merged cache.
                appSize = docs + librarySize + cacheSize
            }
        }
    }

    private func calculateDirectorySize(directory: FileManager.SearchPathDirectory) async -> Int64 {
        guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first else {
            return 0
        }
        return await calculateFolderSize(at: url)
    }

    private func calculateTmpSize() async -> Int64 {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        return await calculateFolderSize(at: tmpURL)
    }

    private func calculateCacheSize() async -> Int64 {
        guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        return await calculateFolderSize(at: cacheURL)
    }

    private func calculateFolderSize(at url: URL) async -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize
            else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    // MARK: - clear cache
    private func clearCache() {
        isClearing = true

        Task {
            guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                await MainActor.run { isClearing = false }
                return
            }

            let fileManager = FileManager.default

            // Clean caches.
            if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
               let contents = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
            {
                for item in contents {
                    try? fileManager.removeItem(at: item)
                }
            }

            // Clean temporary files.
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            if let contents = try? fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil) {
                for item in contents {
                    try? fileManager.removeItem(at: item)
                }
            }

            // Reload.
            await MainActor.run {
                isClearing = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            // Refresh data after a short delay.
            try? await Task.sleep(nanoseconds: 300_000_000)
            loadStorageInfo()
        }
    }

    // MARK: - format
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        StorageSettingsView()
    }
}
