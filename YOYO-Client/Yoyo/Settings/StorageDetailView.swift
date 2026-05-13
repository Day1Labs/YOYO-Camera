import SwiftUI

struct StorageDetailView: View {
    let title: String
    let urls: [URL]
    @State private var items: [StorageItem] = []
    @State private var isLoading = true
    @State private var showDeleteAlert = false
    @State private var itemToDelete: StorageItem?

    init(title: String, url: URL) {
        self.title = title
        urls = [url]
    }

    init(title: String, urls: [URL]) {
        self.title = title
        self.urls = urls
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if items.isEmpty {
                Text(String.settingsStorageNoFiles.localized)
                    .foregroundStyle(.gray)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                            Text(item.path)
                                .font(.system(size: 12))
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatBytes(item.size))
                            .font(.system(size: 14))
                            .foregroundStyle(.gray)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            itemToDelete = item
                            showDeleteAlert = true
                        } label: {
                            Label(String.commonDelete.localized, systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(name: "StorageDetail")
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.04).ignoresSafeArea())
        .onAppear {
            loadItems()
        }
        .alert(String.commonDelete.localized, isPresented: $showDeleteAlert) {
            Button(String.commonCancel.localized, role: .cancel) {}
            Button(String.commonDelete.localized, role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
            }
        } message: {
            if let item = itemToDelete {
                Text(String.settingsStorageDeleteConfirm.localized(item.name))
            }
        }
    }

    private func loadItems() {
        isLoading = true
        Task {
            let fileManager = FileManager.default
            var newItems: [StorageItem] = []

            for url in urls {
                do {
                    let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])

                    for itemURL in contents {
                        let resourceValues = try itemURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                        let isDirectory = resourceValues.isDirectory ?? false
                        let size: Int64

                        if isDirectory {
                            size = await calculateFolderSize(at: itemURL)
                        } else {
                            size = Int64(resourceValues.fileSize ?? 0)
                        }

                        newItems.append(StorageItem(
                            name: itemURL.lastPathComponent,
                            path: itemURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                            size: size,
                            url: itemURL,
                            isDirectory: isDirectory
                        ))
                    }
                } catch {
                    print("Error loading items from \(url.path): \(error)")
                }
            }

            newItems.sort { $0.size > $1.size }

            await MainActor.run {
                items = newItems
                isLoading = false
            }
        }
    }

    private func deleteItem(_ item: StorageItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            withAnimation {
                items.removeAll { $0.id == item.id }
            }
            // Refresh is handled locally after deletion.
        } catch {
            print("Error deleting item: \(error)")
        }
    }

    private func calculateFolderSize(at url: URL) async -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return 0 }

        for fileURL in enumerator.compactMap({ $0 as? URL }) {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory, !isDirectory,
                  let fileSize = resourceValues.fileSize else { continue }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct StorageItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let url: URL
    let isDirectory: Bool
}
