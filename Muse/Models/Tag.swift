import Foundation

struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    let imageId: UUID
    let label: String
    let category: TagCategory
    let confidence: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case imageId = "image_id"
        case label, category, confidence
        case createdAt = "created_at"
    }
}

enum TagCategory: String, Codable, CaseIterable {
    case typography
    case color
    case layout
    case style
}
