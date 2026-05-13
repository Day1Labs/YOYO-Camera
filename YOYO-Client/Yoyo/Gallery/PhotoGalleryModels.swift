import Foundation

// MARK: - Error Types

enum PhotoGalleryError: Error, LocalizedError {
    case permissionDenied
    case networkUnavailable
    case assetNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String.galleryErrorPermissionDenied.localized
        case .networkUnavailable:
            return String.galleryErrorNetworkUnavailable.localized
        case .assetNotFound:
            return String.galleryErrorAssetNotFound.localized
        }
    }
}
