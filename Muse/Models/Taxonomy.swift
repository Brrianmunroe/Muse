import Foundation

/// The controlled vocabulary the AI classifies every image into.
///
/// IMPORTANT: this list MUST stay in sync with the `TAXONOMY` constant in the
/// edge function at `Supabase/functions/analyze-image/index.ts`. Filtering is
/// only reliable because the model can pick *only* from these exact values —
/// so "minimal" and "minimalist" can never split one idea across two filters.
///
/// Facet tags are stored on an image as `"category:value"` tokens, e.g.
/// `"discipline:typography"` or `"color:warm"`.
enum FacetCategory: String, CaseIterable, Identifiable {
    case discipline
    case color
    case mood
    case style

    var id: String { rawValue }

    /// Display label, e.g. "Discipline".
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Allowed values for this category, in display order.
    var values: [String] { Taxonomy.values[self] ?? [] }
}

enum Taxonomy {
    /// Canonical facet → allowed values. Mirror of the edge function's TAXONOMY.
    static let values: [FacetCategory: [String]] = [
        .discipline: ["architecture", "typography", "motion", "product", "graphic",
                      "fashion", "interior", "photography", "illustration"],
        .color: ["warm", "cool", "muted", "vibrant", "monochrome", "pastel", "earthy"],
        .mood: ["calm", "energetic", "playful", "serious", "elegant", "raw"],
        .style: ["minimal", "maximal", "retro", "modern", "editorial", "organic", "geometric"],
    ]

    /// Every valid `"category:value"` token, in category then value order.
    static let allTokens: [String] = FacetCategory.allCases.flatMap { category in
        category.values.map { token(category, $0) }
    }

    /// Build a `"category:value"` token.
    static func token(_ category: FacetCategory, _ value: String) -> String {
        "\(category.rawValue):\(value)"
    }

    /// Parse a `"category:value"` token, returning nil if it isn't valid.
    static func parse(_ token: String) -> (category: FacetCategory, value: String)? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let category = FacetCategory(rawValue: parts[0]),
              category.values.contains(parts[1]) else { return nil }
        return (category, parts[1])
    }

    /// Whether a token is a valid facet token.
    static func isValid(_ token: String) -> Bool { parse(token) != nil }

    /// Validate a raw category/value pair from the model into a token, or nil.
    static func validToken(category: String, value: String) -> String? {
        guard let cat = FacetCategory(rawValue: category.lowercased()),
              cat.values.contains(value.lowercased()) else { return nil }
        return token(cat, value.lowercased())
    }

    /// The bare value of a token (for display), e.g. "warm" from "color:warm".
    static func value(of token: String) -> String { parse(token)?.value ?? token }
}

#if DEBUG
extension Taxonomy {
    /// Deterministic placeholder facets for previewing the filter without the AI —
    /// e.g. in the simulator when Supabase isn't configured. One value per category.
    /// NOT used in release builds.
    static func demoTags(seed: Int) -> [String] {
        FacetCategory.allCases.enumerated().map { index, category in
            let values = category.values
            let pick = abs(seed &* (index + 7)) % values.count
            return token(category, values[pick])
        }
    }
}
#endif
