import SwiftData
import Foundation

@Model
final class LocalMuseImage {
    @Attribute(.unique) var id: UUID
    /// Filename relative to Documents/muse-images/
    var localPath: String
    var thumbnailPath: String?
    var width: Int
    var height: Int
    var notes: String
    var sourceApp: String?
    var createdAt: Date
    var tagLabels: [String]
    /// AI-generated 150–200 char design-language description. `nil` until analyzed.
    var aiDescription: String?
    /// Controlled-vocabulary facet tags as "category:value" tokens (see Taxonomy).
    /// Used only for filtering. Empty until analyzed.
    var facetTags: [String] = []
    /// When facets were last classified. `nil` gates (re)analysis + backfill.
    var facetsAnalyzedAt: Date? = nil
    var isFavorite: Bool = false

    init(
        id: UUID = UUID(),
        localPath: String,
        thumbnailPath: String? = nil,
        width: Int,
        height: Int,
        notes: String = "",
        sourceApp: String? = nil,
        createdAt: Date = .now,
        tagLabels: [String] = [],
        aiDescription: String? = nil,
        facetTags: [String] = [],
        facetsAnalyzedAt: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.localPath = localPath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.notes = notes
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.tagLabels = tagLabels
        self.aiDescription = aiDescription
        self.facetTags = facetTags
        self.facetsAnalyzedAt = facetsAnalyzedAt
        self.isFavorite = isFavorite
    }

    var aspectRatio: CGFloat {
        height > 0 ? CGFloat(width) / CGFloat(height) : 1
    }

    /// Stable Int id for the gallery engine derived from the UUID.
    var intID: Int {
        abs(id.hashValue) & 0x7FFFFFFF
    }

    var asTile: MuseTile {
        MuseTile(
            id: intID,
            aspectRatio: aspectRatio,
            imageID: id,
            thumbnailPath: thumbnailPath,
            localPath: localPath,
            notes: notes,
            createdAt: createdAt,
            tagLabels: tagLabels,
            facetTags: facetTags
        )
    }
}
