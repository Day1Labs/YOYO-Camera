import Foundation
import UIKit

// MARK: - AI Inspiration Service Error

enum AIInspirationServiceError: Error, LocalizedError {
    case noImageProvided
    case imageEncodingFailed
    case notLoggedIn
    case insufficientCredits
    case invalidResponse
    case serverError(Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noImageProvided:
            return String.aiInspirationErrorNoImage.localized
        case .imageEncodingFailed:
            return String.aiInspirationErrorEncoding.localized
        case .notLoggedIn:
            return String.aiInspirationErrorNotLoggedIn.localized
        case .insufficientCredits:
            return String.aiInspirationErrorInsufficientCredits.localized
        case .invalidResponse:
            return String.aiInspirationErrorInvalidResponse.localized
        case let .serverError(code):
            return String.aiInspirationErrorServer.localized(code)
        case .decodingError:
            return String.aiInspirationErrorDecoding.localized
        }
    }
}

// MARK: - AI Inspiration Service

final class AIInspirationService {
    static let shared = AIInspirationService()

    private let baseURL = "https://yoyo.day1-labs.com"

    private init() {}

    /// Maximum side length of uploaded image (pixels)
    private let maxImageDimension: CGFloat = 512

    func fetchInspirations(from image: UIImage) async throws -> ([AIInspiration], Int) {
        guard let token = await AuthService.shared.authToken else {
            throw AIInspirationServiceError.notLoggedIn
        }

        guard image.size.width > 0, image.size.height > 0 else {
            throw AIInspirationServiceError.noImageProvided
        }

        // Resize image if needed to reduce upload size
        let resizedImage = resizeImageIfNeeded(image, maxDimension: maxImageDimension)

        // Compress and encode image to base64
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.7) else {
            throw AIInspirationServiceError.imageEncodingFailed
        }
        let base64Image = imageData.base64EncodedString()

        guard let url = URL(string: "\(baseURL)/api/inspiration") else {
            throw AIInspirationServiceError.invalidResponse
        }

        // Get current app language
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "imageBase64": base64Image,
            "mimeType": "image/jpeg",
            "language": language,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIInspirationServiceError.invalidResponse
        }

        if httpResponse.statusCode == 403 {
            throw AIInspirationServiceError.insufficientCredits
        }

        guard httpResponse.statusCode == 200 else {
            throw AIInspirationServiceError.serverError(httpResponse.statusCode)
        }

        let inspirationResponse = try JSONDecoder().decode(InspirationResponse.self, from: data)

        // Convert response to AIInspiration models
        let inspirations = inspirationResponse.inspirations.map { item in
            // Decode base64 image
            var image: UIImage?
            if !item.imageBase64.isEmpty,
               let imageData = Data(base64Encoded: item.imageBase64)
            {
                image = UIImage(data: imageData)
            }

            return AIInspiration(
                title: item.title,
                description: item.description,
                style: item.style,
                image: image,
                imageGenPrompt: item.imageGenPrompt
            )
        }

        return (inspirations, inspirationResponse.credits)
    }

    func generateImage(for inspiration: AIInspiration, originalImage: UIImage) async throws -> (UIImage, Int) {
        guard let token = await AuthService.shared.authToken else {
            throw AIInspirationServiceError.notLoggedIn
        }

        // Resize image if needed
        let resizedImage = resizeImageIfNeeded(originalImage, maxDimension: maxImageDimension)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.7) else {
            throw AIInspirationServiceError.imageEncodingFailed
        }
        let base64Image = imageData.base64EncodedString()

        guard let url = URL(string: "\(baseURL)/api/inspiration/image") else {
            throw AIInspirationServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "imageBase64": base64Image,
            "mimeType": "image/jpeg",
            "imageGenPrompt": inspiration.imageGenPrompt,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIInspirationServiceError.invalidResponse
        }

        if httpResponse.statusCode == 403 {
            throw AIInspirationServiceError.insufficientCredits
        }

        guard httpResponse.statusCode == 200 else {
            throw AIInspirationServiceError.serverError(httpResponse.statusCode)
        }

        let imageResponse = try JSONDecoder().decode(InspirationImageResponse.self, from: data)

        guard !imageResponse.imageBase64.isEmpty,
              let imageData = Data(base64Encoded: imageResponse.imageBase64),
              let image = UIImage(data: imageData)
        else {
            throw AIInspirationServiceError.decodingError
        }

        return (image, imageResponse.credits)
    }

    // MARK: - Private Helpers

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        // Optimization: only return directly when the size is appropriate and the direction is already positive
        // This ensures that all images with non-.up orientations are redrawn and "baked" in the orientation
        if maxSide <= maxDimension, image.imageOrientation == .up {
            return image
        }

        // Calculate the target size (maintain the aspect ratio of the original image, based on the user's perspective)
        let targetSize: CGSize
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            targetSize = size
        }

        // Use scale = 1.0 to ensure maxDimension is physical pixels, not screen points
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { _ in
            // The draw method will automatically rotate the drawn content according to image.imageOrientation
            // Ensure that the pixel orientation of the final image is consistent with what the user sees (what you see is what you get)
            // Regardless of whether it is a horizontal screen shot or a vertical screen shot, the "top that the user sees" will be converted to the top of the pixel data.
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
