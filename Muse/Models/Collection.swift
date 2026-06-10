import Foundation

struct Collection: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let name: String
    let description: String?
    let coverImageId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, description
        case coverImageId = "cover_image_id"
        case createdAt = "created_at"
    }
}

struct CollectionImage: Codable, Hashable {
    let collectionId: UUID
    let imageId: UUID
    let sortOrder: Int
    let addedAt: Date

    enum CodingKeys: String, CodingKey {
        case collectionId = "collection_id"
        case imageId = "image_id"
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }
}
