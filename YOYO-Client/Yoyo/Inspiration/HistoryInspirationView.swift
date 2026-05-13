import SwiftUI

struct HistoryInspirationView: View {
    @ObservedObject var inspirationManager: InspirationManager
    @Binding var isPresented: Bool
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if inspirationManager.historyInspirations.isEmpty {
                    emptyStateView
                } else {
                    historyListView
                }
            }
            .navigationTitle(String.aiInspirationHistoryTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingClearConfirm = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .disabled(inspirationManager.historyInspirations.isEmpty)
                }
            }
            .confirmationDialog(
                String.aiInspirationHistoryClearConfirm.localized,
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button(String.aiInspirationHistoryClear.localized, role: .destructive) {
                    inspirationManager.clearHistory()
                }
                Button(String.commonCancel.localized, role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.2))

            Text(String.aiInspirationHistoryEmpty.localized)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(40)
    }

    private var historyListView: some View {
        List {
            ForEach(inspirationManager.historyInspirations) { inspiration in
                HistoryInspirationCard(inspiration: inspiration)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onDelete { indexSet in
                inspirationManager.deleteHistoryItem(at: indexSet)
            }
        }
        .listStyle(.plain)
        .padding(.top, 8)
    }
}

struct HistoryInspirationCard: View {
    let inspiration: AIInspiration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Image Thumbnail
                if let image = inspiration.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(inspiration.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        if !inspiration.style.isEmpty {
                            Text(inspiration.style)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }

                    Text(inspiration.description)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    Text(relativeTimeString(from: inspiration.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return String.timeJustNow.localized
        } else if seconds < 3600 {
            return String.timeMinutesAgo.localized(seconds / 60)
        } else if seconds < 86400 {
            return String.timeHoursAgo.localized(seconds / 3600)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}
