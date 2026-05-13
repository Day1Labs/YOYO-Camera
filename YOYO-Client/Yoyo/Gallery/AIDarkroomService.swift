import Foundation
import UIKit

// MARK: - AI Darkroom Service

enum AIDarkroomOperation: String {
    case portraitEnhance = "portrait_enhance"
    case idPhoto = "id_photo"
    case professionalPhoto = "professional_photo"
    case socialAvatar = "social_avatar"
    case removeObjects = "remove_objects"
    case blurRepair = "blur_repair"
    case colorGrading = "color_grading"
    case fixClosedEyes = "fix_closed_eyes"
}

struct AIDarkroomResponse: Codable {
    let imageBase64: String
    let imageMimeType: String
    let credits: Int
}

final class AIDarkroomService {
    static let shared = AIDarkroomService()

    private let baseURL = "https://yoyo.day1-labs.com"
    private let maxImageDimension: CGFloat = 1024 // Supported by Gemini Flash 2.5

    private init() {}

    func processImage(
        image: UIImage,
        operation: AIDarkroomOperation,
        options: [String: Any] = [:]
    ) async throws -> (UIImage, Int) {
        guard let token = await AuthService.shared.authToken else {
            throw AIInspirationServiceError.notLoggedIn
        }

        // Resize and encode
        let resizedImage = resizeImageIfNeeded(image, maxDimension: maxImageDimension)
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw AIInspirationServiceError.imageEncodingFailed
        }
        let base64Image = imageData.base64EncodedString()

        guard let url = URL(string: "\(baseURL)/api/ai_darkroom/process") else {
            throw AIInspirationServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "imageBase64": base64Image,
            "mimeType": "image/jpeg",
            "operation": operation.rawValue,
            "options": options,
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

        let aiResponse = try JSONDecoder().decode(AIDarkroomResponse.self, from: data)

        guard let imageDataResponse = Data(base64Encoded: aiResponse.imageBase64),
              let resultImage = UIImage(data: imageDataResponse)
        else {
            throw AIInspirationServiceError.decodingError
        }

        return (resultImage, aiResponse.credits)
    }

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        if maxSide <= maxDimension, image.imageOrientation == .up {
            return image
        }

        let targetSize: CGSize
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            targetSize = size
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
