import Foundation
import Supabase

final class StorageService {
    private let client: SupabaseClient?
    private let bucketName = "inspiration-images"

    init(client: SupabaseClient? = SupabaseService.shared.client) {
        self.client = client
    }

    func uploadImage(data: Data, userId: UUID) async throws -> String {
        guard let client else { throw MuseError.notConfigured }
        let fileName = "\(userId)/\(UUID().uuidString).jpg"

        try await client.storage
            .from(bucketName)
            .upload(
                fileName,
                data: data,
                options: .init(contentType: "image/jpeg")
            )

        return fileName
    }

    func getImageURL(path: String) throws -> URL {
        guard let client else { throw MuseError.notConfigured }
        return try client.storage
            .from(bucketName)
            .getPublicURL(path: path)
    }
}
