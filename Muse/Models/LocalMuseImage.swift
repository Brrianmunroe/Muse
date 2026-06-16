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
            tagLabels: tagLabels
        )
    }
}
