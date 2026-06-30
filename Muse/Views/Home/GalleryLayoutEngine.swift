import SwiftUI

/// Where a single tile sits inside the gallery's content space.
struct TilePlacement: Equatable {
    var frame: CGRect
    var rotation: Angle

    static let zero = TilePlacement(frame: .zero, rotation: .zero)
}

/// The full result of laying out every tile for one mode.
struct GalleryLayout {
    var placements: [Int: TilePlacement]
    var contentSize: CGSize
    /// Where the viewport should start (e.g. centered on the vast canvas, top of the bento grid).
    var initialOffset: CGPoint
}

enum GalleryLayoutEngine {

    static let vastSpacing: CGFloat = 16
    static let vastTileWidth: CGFloat = 150
    /// Empty breathing room around the outermost tiles — "one image" of margin so the
    /// canvas stays snug and the grid never drifts into a sea of empty space.
    static let vastMargin: CGFloat = vastTileWidth

    static func layout(mode: GalleryLayoutMode, tiles: [any GalleryTile], viewport: CGSize) -> GalleryLayout {
        guard viewport.width > 0, viewport.height > 0, !tiles.isEmpty else {
            return GalleryLayout(placements: [:], contentSize: viewport, initialOffset: .zero)
        }
        switch mode {
        case .vast: return vastLayout(tiles: tiles, viewport: viewport)
        case .bento: return bentoLayout(tiles: tiles, viewport: viewport)
        case .feed: return feedLayout(tiles: tiles, viewport: viewport)
        }
    }

    // MARK: - Vast (packed collage / galaxy)

    private static func vastLayout(tiles: [any GalleryTile], viewport: CGSize) -> GalleryLayout {
        let spacing = vastSpacing
        let tileWidth = vastTileWidth
        let count = tiles.count

        // Roughly-square board: ~sqrt(count) columns. Each tile drops into the
        // currently-shortest column (masonry), so the varied photo heights interleave
        // into a collage with no aligned rows.
        let columns = max(3, Int(Double(count).squareRoot().rounded()))
        let pitch = tileWidth + spacing

        // Give each column a different vertical start so the top edge is ragged and the
        // whole board reads as an off-center collage rather than tidy aligned columns.
        var columnBottoms = (0..<columns).map { c -> CGFloat in
            let phase = CGFloat((c * 53) % 100) / 100
            return vastMargin + phase * tileWidth * 0.6
        }
        var placements: [Int: TilePlacement] = [:]

        for tile in tiles {
            // Shortest column wins; ties break to the leftmost for a stable layout.
            var col = 0
            for c in 1..<columns where columnBottoms[c] < columnBottoms[col] - 0.5 {
                col = c
            }
            let height = tileWidth / tile.aspectRatio
            let x = vastMargin + CGFloat(col) * pitch
            let y = columnBottoms[col]

            placements[tile.id] = TilePlacement(
                frame: CGRect(x: x, y: y, width: tileWidth, height: height),
                rotation: .zero
            )
            columnBottoms[col] += height + spacing
        }

        let maxRight = placements.values.map(\.frame.maxX).max() ?? viewport.width
        let maxBottom = placements.values.map(\.frame.maxY).max() ?? viewport.height
        let contentWidth = max(maxRight + vastMargin, viewport.width)
        let contentHeight = max(maxBottom + vastMargin, viewport.height)
        let contentSize = CGSize(width: contentWidth, height: contentHeight)
        let initialOffset = CGPoint(
            x: (contentSize.width - viewport.width) / 2,
            y: (contentSize.height - viewport.height) / 2
        )
        return GalleryLayout(placements: placements, contentSize: contentSize, initialOffset: initialOffset)
    }

    // MARK: - Bento (masonry grid)

    private static func bentoLayout(tiles: [any GalleryTile], viewport: CGSize) -> GalleryLayout {
        let padding: CGFloat = 16
        let gap: CGFloat = 10
        // Clearance for the "Your inspiration" header, which overlays the canvas
        // rather than insetting it (so mode morphs never resize mid-flight).
        let topInset: CGFloat = 112
        let columnWidth = (viewport.width - padding * 2 - gap) / 2
        var columnBottoms: [CGFloat] = [topInset, topInset]

        var placements: [Int: TilePlacement] = [:]
        for tile in tiles {
            let column = columnBottoms[0] <= columnBottoms[1] ? 0 : 1
            let x = padding + CGFloat(column) * (columnWidth + gap)
            let height = columnWidth / tile.aspectRatio

            placements[tile.id] = TilePlacement(
                frame: CGRect(x: x, y: columnBottoms[column], width: columnWidth, height: height),
                rotation: .zero
            )
            columnBottoms[column] += height + gap
        }

        let contentHeight = max((columnBottoms.max() ?? 0) - gap + padding, viewport.height)
        return GalleryLayout(
            placements: placements,
            contentSize: CGSize(width: viewport.width, height: contentHeight),
            initialOffset: .zero
        )
    }

    // MARK: - Feed (one tile per page)

    private static func feedLayout(tiles: [any GalleryTile], viewport: CGSize) -> GalleryLayout {
        let pageHeight = viewport.height
        let horizontalInset: CGFloat = 16
        let verticalInset: CGFloat = 56

        var placements: [Int: TilePlacement] = [:]
        for (index, tile) in tiles.enumerated() {
            var width = viewport.width - horizontalInset * 2
            var height = width / tile.aspectRatio
            let maxHeight = pageHeight - verticalInset * 2
            if height > maxHeight {
                height = maxHeight
                width = height * tile.aspectRatio
            }

            let pageCenterY = CGFloat(index) * pageHeight + pageHeight / 2
            placements[tile.id] = TilePlacement(
                frame: CGRect(
                    x: (viewport.width - width) / 2,
                    y: pageCenterY - height / 2,
                    width: width,
                    height: height
                ),
                rotation: .zero
            )
        }

        return GalleryLayout(
            placements: placements,
            contentSize: CGSize(width: viewport.width, height: pageHeight * CGFloat(tiles.count)),
            initialOffset: .zero
        )
    }
}
