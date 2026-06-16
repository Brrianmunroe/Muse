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

    static let vastSpacing: CGFloat = 40
    static let vastTileWidth: CGFloat = 150

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

    // MARK: - Vast (hexagonal galaxy)

    private static func vastLayout(tiles: [any GalleryTile], viewport: CGSize) -> GalleryLayout {
        let spacing = vastSpacing
        let tileWidth = vastTileWidth
        let count = tiles.count
        let columns = max(3, Int(ceil(sqrt(Double(count) * 1.1))))
        let horizontalPitch = tileWidth + spacing

        // Size each row band to fit the tallest tile so nothing overlaps vertically.
        let minAspect = tiles.map(\.aspectRatio).min() ?? 1
        let cellHeight = tileWidth / minAspect
        let verticalPitch = cellHeight + spacing

        var placements: [Int: TilePlacement] = [:]
        var tileIndex = 0
        var row = 0
        var rowY = spacing

        while tileIndex < count {
            let isOffsetRow = row % 2 == 1
            var rowMaxHeight: CGFloat = 0
            var rowEntries: [(any GalleryTile, Int)] = []

            for col in 0..<columns {
                guard tileIndex < count else { break }
                let tile = tiles[tileIndex]
                let height = tileWidth / tile.aspectRatio
                rowMaxHeight = max(rowMaxHeight, height)
                rowEntries.append((tile, col))
                tileIndex += 1
            }

            for (tile, col) in rowEntries {
                let height = tileWidth / tile.aspectRatio
                let rowOffset = isOffsetRow ? horizontalPitch / 2 : 0
                let x = spacing + rowOffset + CGFloat(col) * horizontalPitch
                let y = rowY + (rowMaxHeight - height) / 2

                placements[tile.id] = TilePlacement(
                    frame: CGRect(x: x, y: y, width: tileWidth, height: height),
                    rotation: .zero
                )
            }

            rowY += verticalPitch
            row += 1
        }

        let maxRight = placements.values.map(\.frame.maxX).max() ?? viewport.width
        let contentWidth = max(maxRight + spacing, viewport.width * 2.5)
        let contentHeight = max(rowY, viewport.height * 2.5)
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
        let horizontalInset: CGFloat = 24
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
