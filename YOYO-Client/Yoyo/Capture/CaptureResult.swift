import Foundation
import UIKit

/// CaptureResult
struct CaptureResult: Equatable {
    let originalImage: UIImage
    let filteredImage: UIImage
    let metadata: [String: Any]?
    let livePhotoURL: URL?
    /// originalJPEGdata, data
    let originalImageData: Data?
    /// videoURL
    let videoURL: URL?
    /// originalvideoURL(saveoriginalvideouse)
    let originalVideoURL: URL?
    /// whethervideo
    let isVideo: Bool

    /// whetherRAWformat
    let isRaw: Bool

    init(originalImage: UIImage = UIImage(),
         filteredImage: UIImage = UIImage(),
         metadata: [String: Any]? = nil,
         livePhotoURL: URL? = nil,
         originalImageData: Data? = nil,
         videoURL: URL? = nil,
         originalVideoURL: URL? = nil,
         isRaw: Bool = false)
    {
        self.originalImage = originalImage
        self.filteredImage = filteredImage
        self.metadata = metadata
        self.livePhotoURL = livePhotoURL
        self.originalImageData = originalImageData
        self.videoURL = videoURL
        self.originalVideoURL = originalVideoURL
        isVideo = videoURL != nil
        self.isRaw = isRaw
    }

    static func == (lhs: CaptureResult, rhs: CaptureResult) -> Bool {
        // only livePhotoURL and metadata, imagenot ()
        lhs.livePhotoURL == rhs.livePhotoURL &&
            lhs.videoURL == rhs.videoURL &&
            lhs.originalVideoURL == rhs.originalVideoURL &&
            lhs.metadata as NSDictionary? == rhs.metadata as NSDictionary?
    }
}
