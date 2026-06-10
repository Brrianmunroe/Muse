import Foundation

struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    let email: String
    let displayName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}
