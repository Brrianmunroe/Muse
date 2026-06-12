import UIKit
import SwiftData
import Supabase

/// Asks the `analyze-image` Supabase Edge Function for an AI design description
/// and tags. The Anthropic key lives in the function, never in the app.
enum ImageAnalysisService {

    enum AnalysisError: Error {
        case notConfigured
        case encodingFailed
    }

    private struct Request: Encodable {
        let image_base64: String
        let media_type: String
    }

    private struct Result: Decodable {
        let description: String
        let tags: [String]
    }

    /// Tracks images already being analyzed so we never fire two calls for one.
    @MainActor private static var inFlight: Set<UUID> = []

    /// Downscale → JPEG → base64 → call the function. Returns the design
    /// description (trimmed to ~200 chars) and tags.
    static func analyze(localPath: String) async throws -> (description: String, tags: [String]) {
        guard let client = SupabaseService.shared.client else {
            throw AnalysisError.notConfigured
        }

        // ~1024px is plenty for description and keeps image tokens (and cost) low.
        guard let image = ImageCache.display(for: localPath, maxDimension: 1024),
              let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.encodingFailed
        }
        let base64 = jpeg.base64EncodedString()

        let result: Result = try await client.functions.invoke(
            "analyze-image",
            options: FunctionInvokeOptions(
                body: Request(image_base64: base64, media_type: "image/jpeg")
            )
        )

        let description = String(result.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220))
        return (description, result.tags)
    }

    /// Analyze once and persist onto the record. No-ops if already described,
    /// already running, or Supabase isn't configured.
    @MainActor
    static func analyzeIfNeeded(_ image: LocalMuseImage, context: ModelContext) {
        guard image.aiDescription == nil,
              SupabaseService.shared.isConfigured,
              !inFlight.contains(image.id) else { return }

        inFlight.insert(image.id)
        let localPath = image.localPath
        let imageID = image.id

        Task {
            defer { Task { @MainActor in inFlight.remove(imageID) } }
            guard let (description, tags) = try? await analyze(localPath: localPath) else { return }
            await MainActor.run {
                image.aiDescription = description
                if !tags.isEmpty { image.tagLabels = tags }
                try? context.save()
            }
        }
    }
}
