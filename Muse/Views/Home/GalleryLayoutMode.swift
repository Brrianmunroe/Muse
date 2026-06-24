import SwiftUI

/// The three ways content can be arranged on the home page.
enum GalleryLayoutMode: String, CaseIterable, Identifiable {
    /// Honeycomb hex grid on a large pannable canvas.
    case vast
    /// Pinterest-style masonry grid, scrolled vertically.
    case bento
    /// One image per screen, swiped vertically.
    case feed

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .vast: return "square.grid.3x3.fill"
        case .bento: return "square.grid.2x2.fill"
        case .feed: return "rectangle.portrait.fill"
        }
    }

    var label: String {
        switch self {
        case .vast: return "Vast"
        case .bento: return "Bento"
        case .feed: return "Feed"
        }
    }
}

/// Lightweight tag for preview tiles (mirrors Tag without UUID/imageId).
struct TagPreview: Identifiable, Equatable {
    let id: String
    let label: String
    let category: TagCategory
}

/// Minimal contract the layout engine needs from any tile type.
protocol GalleryTile: Identifiable where ID == Int {
    var aspectRatio: CGFloat { get }
}

/// Real tile backed by a persisted image — carries just what the canvas needs.
struct MuseTile: GalleryTile, Equatable {
    let id: Int
    let aspectRatio: CGFloat
    let imageID: UUID
    let thumbnailPath: String?
    let localPath: String
    let notes: String
    let createdAt: Date
    let tagLabels: [String]
    /// Controlled facet tokens ("category:value") for filtering. See Taxonomy.
    let facetTags: [String]
}

/// Placeholder content tile used until real images are wired in.
struct SampleTile: GalleryTile, Equatable {
    let id: Int
    let topColor: Color
    let bottomColor: Color
    /// width / height
    let aspectRatio: CGFloat
    let tags: [TagPreview]
    let aiDescription: String
    let notes: String
    let sourceApp: String?
    let createdAt: Date

    var gradient: LinearGradient {
        LinearGradient(
            colors: [topColor, bottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let samples: [SampleTile] = {
        let palette: [(String, String)] = [
            ("D8C4B8", "C0A8A0"), ("A8B4A0", "8FA08A"), ("B0A8C0", "9890AC"),
            ("C4B8A0", "B0A488"), ("98A8B8", "8294A8"), ("C0A8A0", "A88E86"),
            ("B8C4A8", "A2B090"), ("A0A8B8", "8A92A4"), ("C8B8A8", "B4A290"),
            ("E8C5C4", "C4706E"), ("C9D4E6", "6B80A3"), ("EDDAAE", "D4B872"),
            ("D3D1C7", "8A877E"), ("DDD9CF", "B8B4A8"), ("D8C4B8", "A8B4A0"),
            ("B0A8C0", "C9D4E6"), ("C4B8A0", "EDDAAE"), ("98A8B8", "B0A8C0"),
            ("C0A8A0", "E8C5C4"), ("B8C4A8", "D3D1C7")
        ]
        let aspects: [CGFloat] = [
            0.70, 1.00, 0.80, 1.30, 0.75, 1.00, 0.66, 1.20, 0.80, 1.00,
            0.70, 1.40, 0.90, 0.75, 1.00, 0.80, 1.25, 0.70, 1.00, 0.85
        ]
        let tagSets: [[(String, TagCategory)]] = [
            [("serif heading", .typography), ("warm palette", .color), ("editorial", .style)],
            [("organic layout", .layout), ("earth tones", .color)],
            [("high contrast", .typography), ("asymmetric grid", .layout)],
            [("muted tones", .color), ("minimal", .style)],
            [("sans-serif", .typography), ("cool palette", .color)],
            [("editorial", .style), ("warm palette", .color), ("serif heading", .typography)],
            [("grid layout", .layout), ("neutral", .color)],
            [("bold type", .typography), ("high contrast", .typography)],
            [("soft gradient", .color), ("contemporary", .style)],
            [("classic serif", .typography), ("editorial", .style)],
            [("pastel", .color), ("light layout", .layout)],
            [("golden ratio", .layout), ("warm palette", .color)],
            [("monochrome", .color), ("minimal", .style)],
            [("hand-drawn", .style), ("sketch layout", .layout)],
            [("retro", .style), ("warm palette", .color)],
            [("blue tones", .color), ("structured grid", .layout)],
            [("ochre accent", .color), ("editorial", .style)],
            [("layered", .layout), ("depth", .style)],
            [("blush tones", .color), ("soft serif", .typography)],
            [("natural", .style), ("green palette", .color)]
        ]
        let descriptions = [
            "An editorial layout pairing a large serif headline with generous whitespace and a restrained warm palette.",
            "Organic composition with soft green tones and an asymmetric crop that draws the eye to the lower third.",
            "High-contrast typography treatment with a structured grid and cool blue-grey undertones throughout.",
            "Muted, desaturated color story with minimal elements and calm negative space.",
            "Clean sans-serif hierarchy over a cool-toned background with subtle geometric accents.",
            "Warm editorial spread featuring layered typography and an inviting earth-tone palette.",
            "Neutral grid-based layout with balanced proportions and restrained ornamentation.",
            "Bold typographic scale contrast against a soft lavender field.",
            "Contemporary gradient wash with gentle tonal shifts and an airy, open feel.",
            "Classic serif display type anchored by structured margins and editorial pacing.",
            "Pastel color blocking with a light, open layout and playful proportions.",
            "Golden-ratio composition with ochre highlights and warm ambient tones.",
            "Monochrome palette emphasizing texture and form over color.",
            "Hand-drawn aesthetic with sketch-like lines and an informal, creative layout.",
            "Retro-inspired color blocking with nostalgic warmth and bold shapes.",
            "Cool blue palette with a precise structured grid and crisp alignment.",
            "Ochre accent color punctuating an otherwise neutral editorial frame.",
            "Layered depth with overlapping elements and a sense of dimensional space.",
            "Soft blush tones paired with delicate serif letterforms.",
            "Natural, earthy palette with an unhurried editorial rhythm."
        ]
        let sources = [
            "Instagram", "Pinterest", "Safari", "Behance", "Dribbble",
            "Instagram", "Pinterest", "Are.na", "Safari", "Instagram",
            "Pinterest", "Behance", "Dribbble", "Safari", "Instagram",
            "Pinterest", "Are.na", "Behance", "Instagram", "Safari"
        ]
        let sampleNotes = [
            "", "", "Love the type scale here", "", "",
            "Reference for Q2 mood board", "", "", "Try this palette for the landing page", "",
            "", "", "", "Save for poster layout", "",
            "", "Good grid reference", "", "Bookmark for serif pairing", ""
        ]
        let calendar = Calendar.current
        let now = Date()

        return palette.enumerated().map { index, pair in
            let tagPreviews = tagSets[index].enumerated().map { tagIndex, tag in
                TagPreview(id: "\(index)-\(tagIndex)", label: tag.0, category: tag.1)
            }
            let daysAgo = index * 3
            let createdAt = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now

            return SampleTile(
                id: index,
                topColor: Color(hex: pair.0),
                bottomColor: Color(hex: pair.1),
                aspectRatio: aspects[index],
                tags: tagPreviews,
                aiDescription: descriptions[index],
                notes: sampleNotes[index],
                sourceApp: sources[index],
                createdAt: createdAt
            )
        }
    }()
}
