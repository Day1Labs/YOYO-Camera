import SwiftUI
import UIKit

// MARK: - AI Inspiration Model

struct AIInspiration: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let description: String
    let style: String
    var image: UIImage?
    let imageGenPrompt: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, style, imageGenPrompt, createdAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        style: String = "",
        image: UIImage? = nil,
        imageGenPrompt: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.style = style
        self.image = image
        self.imageGenPrompt = imageGenPrompt
        self.createdAt = createdAt
    }
}

// MARK: - API Response Models

struct InspirationResponse: Codable {
    let inspirations: [InspirationItemResponse]
    let credits: Int
}

struct InspirationItemResponse: Codable {
    let title: String
    let description: String
    let style: String
    let imageBase64: String
    let imageMimeType: String
    let imageGenPrompt: String
}

struct InspirationImageResponse: Codable {
    let imageBase64: String
    let imageMimeType: String
    let credits: Int
}
