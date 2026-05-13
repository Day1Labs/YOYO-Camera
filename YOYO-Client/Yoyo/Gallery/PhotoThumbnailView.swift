import Photos
import SwiftData
import SwiftUI

struct PhotoThumbnailView: View {
    let photo: PhotoAsset
    var isSelected: Bool = false

    var body: some View {
        let baseColor = Color(red: 0.12, green: 0.12, blue: 0.12)

        ZStack(alignment: .topTrailing) {
            // Asynchronous image loading.
            AsyncThumbnailImage(
                assetIdentifier: photo.assetIdentifier,
                photoId: photo.id.uuidString
            )
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity
            )

            // Media type indicator (lower left corner).
            VStack {
                Spacer()
                HStack {
                    // LivePhoto indicator
                    if photo.isLivePhoto, !isSelected {
                        Image(systemName: "livephoto")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 12))
                            .padding(6)
                    }

                    // Video indicator
                    if photo.mediaType == 2, !isSelected {
                        if let duration = photo.videoDuration {
                            Text(formatDuration(duration))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(6)
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        } else {
                            Image(systemName: "video")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 12))
                                .padding(6)
                        }
                    }

                    Spacer()
                }
            }
            .transition(.opacity)

            // Favorite indicator
            if photo.isFavorite, !isSelected {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red.opacity(0.8))
                            .font(.system(size: 12))
                            .padding(4)
                            .background(Circle().fill(baseColor.opacity(0.6)))
                            .padding(6)
                    }
                }
                .transition(.opacity)
            }

            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .background(Circle().fill(Color.white))
                    .clipShape(Circle())
                    .padding(6)
                    .transition(.scale.animation(.spring(response: 0.3, dampingFraction: 0.6)))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
        .cornerRadius(2)
        .background(
            // Simplify background effects and improve performance.
            RoundedRectangle(cornerRadius: 2)
                .fill(baseColor)
                .shadow(
                    color: isSelected ? .accentColor.opacity(0.3) : .black.opacity(0.3),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: 2
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
