import SwiftUI

/// The card that floats above the search bar while searching: the active-filter
/// pill tray plus tag suggestions for the current query. The search field itself
/// lives in `HomeView.searchBar` (a single morphing capsule).
struct SearchFilterView: View {
    @Binding var searchText: String
    @Binding var activeFacets: Set<String>

    /// Shown before the user starts typing — a calm handful, not all 29.
    private let starters = [
        "discipline:typography", "color:warm", "style:minimal",
        "mood:calm", "style:editorial", "discipline:architecture",
    ]

    /// Tag suggestions for the trailing word (or starters when empty).
    private var suggestions: [String] {
        let pool = Taxonomy.allTokens.filter { !activeFacets.contains($0) }
        let trailing = searchText.split(separator: " ").last.map { String($0).lowercased() } ?? ""
        guard !trailing.isEmpty else {
            return starters.filter { !activeFacets.contains($0) }
        }
        return Array(pool.filter { Taxonomy.value(of: $0).contains(trailing) }.prefix(8))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !activeFacets.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeFacets.removeAll()
                            searchText = ""
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .overlay(Capsule().stroke(MuseTheme.Semantic.dividerDefault, lineWidth: 1))
                            .foregroundStyle(MuseTheme.Semantic.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(suggestions, id: \.self) { token in
                    Button { lock(token) } label: {
                        Text(Taxonomy.value(of: token))
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(tint(token).bg, in: Capsule())
                            .foregroundStyle(tint(token).fg)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(MuseTheme.Semantic.navBarSurface.opacity(0.8)))
                .overlay(Capsule().stroke(MuseTheme.Semantic.navBarStroke, lineWidth: 0.5))
        }
        .clipShape(Capsule())
        .overlay {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [MuseTheme.Semantic.navBarSurface, MuseTheme.Semantic.navBarSurface.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                Spacer()
                LinearGradient(
                    colors: [MuseTheme.Semantic.navBarSurface.opacity(0), MuseTheme.Semantic.navBarSurface],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }

    /// Commit a suggestion: add the facet and strip the trailing partial word
    /// that produced it, so it doesn't double-filter as free text.
    private func lock(_ token: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = activeFacets.insert(token)
        }
        var parts = searchText.split(separator: " ").map(String.init)
        if let last = parts.last?.lowercased(), Taxonomy.value(of: token).hasPrefix(last) {
            parts.removeLast()
        }
        searchText = parts.joined(separator: " ")
    }

    /// Category-tinted colors for a suggestion chip.
    private func tint(_ token: String) -> (bg: Color, fg: Color) {
        switch Taxonomy.parse(token)?.category {
        case .discipline: return (MuseTheme.Alias.fillTintBlue, MuseTheme.Alias.textOnTintBlue)
        case .color: return (MuseTheme.Alias.fillTintOchre, MuseTheme.Alias.textOnTintOchre)
        case .mood: return (MuseTheme.Alias.fillTintRed, MuseTheme.Alias.textOnTintRed)
        case .style, .none: return (MuseTheme.Alias.fillTintNeutral, MuseTheme.Alias.textOnTintNeutral)
        }
    }
}
