import Foundation

struct MuseImage: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let storagePath: String
    let thumbnailPath: String?
    let width: Int?
    let height: Int?
    let sourceApp: String?
    let aiDescription: String?
    let notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case storagePath = "storage_path"
        case thumbnailPath = "thumbnail_path"
        case width, height
        case sourceApp = "source_app"
        case aiDescription = "ai_description"
        case notes
        case createdAt = "created_at"
    }
}
