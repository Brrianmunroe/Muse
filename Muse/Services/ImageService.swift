import Foundation
import Supabase

final class ImageService {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseService.shared.client) {
        self.client = client
    }

    func fetchImages(for userId: UUID) async throws -> [MuseImage] {
        guard let client else { throw MuseError.notConfigured }
        return try await client
            .from("images")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func insertImage(_ image: MuseImage) async throws {
        guard let client else { throw MuseError.notConfigured }
        try await client
            .from("images")
            .insert(image)
            .execute()
    }

    func fetchTags(for imageId: UUID) async throws -> [Tag] {
        guard let client else { throw MuseError.notConfigured }
        return try await client
            .from("tags")
            .select()
            .eq("image_id", value: imageId.uuidString)
            .execute()
            .value
    }

    func updateNotes(for imageId: UUID, notes: String) async throws {
        guard let client else { throw MuseError.notConfigured }
        try await client
            .from("images")
            .update(["notes": notes])
            .eq("id", value: imageId.uuidString)
            .execute()
    }
}
