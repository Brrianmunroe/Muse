import Foundation

/// How the gallery orders images when no free-text search is ranking them.
enum GallerySortOrder: String, CaseIterable, Identifiable {
    case recency
    case oldest
    case discipline
    case color

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recency: return "Newest"
        case .oldest: return "Oldest"
        case .discipline: return "By type"
        case .color: return "By color"
        }
    }

    /// SF Symbol shown on the sort pill.
    var iconName: String {
        switch self {
        case .recency: return "arrow.down"
        case .oldest: return "arrow.up"
        case .discipline: return "square.grid.2x2"
        case .color: return "paintpalette"
        }
    }

    /// The facet a grouping sort keys on, if any.
    var groupingCategory: FacetCategory? {
        switch self {
        case .discipline: return .discipline
        case .color: return .color
        case .recency, .oldest: return nil
        }
    }

    /// Next order when the sort pill is tapped.
    var next: GallerySortOrder {
        let all = GallerySortOrder.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}
